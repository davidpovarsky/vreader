// Purpose: Four-stage scraping pipeline connecting BookSource model (D01),
// HTTP client (D02), and rule engine (D03) into an end-to-end flow.
// Stages: Search -> BookInfo -> TOC -> Content.
//
// Key decisions:
// - Actor-isolated for thread safety during concurrent scraping.
// - HTTP fetching abstracted via HTMLFetchProvider closure for testability.
// - Progress callback reports current stage to UI.
// - Pagination support for TOC (nextTocUrl) and content (nextContentUrl).
// - Max pagination depth to prevent infinite loops.
//
// @coordinates-with: PipelineTypes.swift, BookSource.swift, BookSourceRules.swift,
//   RuleEngine.swift, BookSourceHTTPClient.swift, ChapterCache.swift

import Foundation

/// Four-stage scraping pipeline for BookSource web scraping.
///
/// Stages:
/// 1. **Search**: Replace `{{key}}` in searchURL, fetch, apply ruleSearch.
/// 2. **BookInfo**: Fetch bookUrl, apply ruleBookInfo, extract metadata + tocUrl.
/// 3. **TOC**: Fetch tocUrl, apply ruleToc, extract chapter list. Handle nextTocUrl.
/// 4. **Content**: Fetch chapterUrl, apply ruleContent, clean text. Handle nextContentUrl.
actor BookSourcePipeline {

    /// Maximum number of pagination pages to follow (prevents infinite loops).
    private let maxPaginationDepth: Int

    /// The HTML fetch provider (injectable for testing).
    private let fetchHTML: HTMLFetchProvider

    /// Optional chapter cache for offline reading (D06).
    private let chapterCache: ChapterCache?

    /// Creates a pipeline with the given fetch provider.
    ///
    /// - Parameters:
    ///   - fetchHTML: Closure to fetch HTML from a URL.
    ///   - maxPaginationDepth: Max pages to follow for pagination (default 50).
    ///   - chapterCache: Optional cache for chapter content (default nil).
    init(
        fetchHTML: @escaping HTMLFetchProvider,
        maxPaginationDepth: Int = 50,
        chapterCache: ChapterCache? = nil
    ) {
        self.fetchHTML = fetchHTML
        self.maxPaginationDepth = maxPaginationDepth
        self.chapterCache = chapterCache
    }

    // MARK: - Stage 1: Search

    /// Searches for books using the source's search rules.
    ///
    /// Replaces `{{key}}` in the source's searchURL with the keyword,
    /// fetches the page, and applies ruleSearch to extract book results.
    func search(
        source: BookSourceSnapshot,
        keyword: String,
        progress: (@Sendable (PipelineStage) -> Void)? = nil
    ) async throws -> [BookSearchResult] {
        try Task.checkCancellation()
        progress?(.search)

        guard let searchRule = source.ruleSearch else {
            throw PipelineError.missingSearchRule
        }
        guard let searchURLTemplate = source.searchURL,
              !searchURLTemplate.isEmpty else {
            throw PipelineError.missingSearchURL
        }

        let encoded = keyword.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? keyword
        let urlString = searchURLTemplate.replacingOccurrences(
            of: "{{key}}", with: encoded
        )
        guard let url = URL(string: urlString) else {
            throw PipelineError.invalidURL(urlString)
        }

        let html = try await fetchHTML(url, source.parsedHeaders)

        guard let bookListRule = searchRule.bookList, !bookListRule.isEmpty else {
            return []
        }

        let bookElements = RuleEngine.evaluateRawHTML(
            rule: bookListRule, html: html, baseURL: url
        )
        guard !bookElements.isEmpty else { return [] }

        return bookElements.map { elementHTML in
            BookSearchResult(
                name: extractField(searchRule.name, html: elementHTML, baseURL: url),
                author: extractField(searchRule.author, html: elementHTML, baseURL: url),
                bookUrl: extractField(searchRule.bookUrl, html: elementHTML, baseURL: url),
                coverUrl: extractField(searchRule.coverUrl, html: elementHTML, baseURL: url)
            )
        }
    }

    // MARK: - Stage 2: Book Info

    /// Extracts book detail information from a book's detail page.
    func bookInfo(
        source: BookSourceSnapshot,
        bookUrl: String,
        progress: (@Sendable (PipelineStage) -> Void)? = nil
    ) async throws -> BookDetail {
        try Task.checkCancellation()
        progress?(.bookInfo)

        guard let infoRule = source.ruleBookInfo else {
            throw PipelineError.missingBookInfoRule
        }

        let resolved = resolveURL(bookUrl, against: source.sourceURL)
        guard let url = URL(string: resolved) else {
            throw PipelineError.invalidURL(resolved)
        }

        let html = try await fetchHTML(url, source.parsedHeaders)

        return BookDetail(
            name: extractField(infoRule.name, html: html, baseURL: url),
            author: extractField(infoRule.author, html: html, baseURL: url),
            intro: extractField(infoRule.intro, html: html, baseURL: url),
            coverUrl: extractField(infoRule.coverUrl, html: html, baseURL: url),
            tocUrl: extractField(infoRule.tocUrl, html: html, baseURL: url)
        )
    }

    // MARK: - Stage 3: Chapters (TOC)

    /// Extracts the chapter list from a book's table of contents page.
    /// Handles pagination via nextTocUrl for multi-page chapter lists.
    func chapters(
        source: BookSourceSnapshot,
        tocUrl: String,
        progress: (@Sendable (PipelineStage) -> Void)? = nil
    ) async throws -> [ChapterInfo] {
        try Task.checkCancellation()
        progress?(.toc)

        guard let tocRule = source.ruleToc else {
            throw PipelineError.missingTocRule
        }

        var allChapters: [ChapterInfo] = []
        var currentUrlString: String? = tocUrl
        var pagesFollowed = 0

        while let urlStr = currentUrlString,
              pagesFollowed < maxPaginationDepth {
            try Task.checkCancellation()

            let resolved = resolveURL(urlStr, against: source.sourceURL)
            guard let url = URL(string: resolved) else { break }

            let html = try await fetchHTML(url, source.parsedHeaders)

            let chapterElements: [String]
            if let listRule = tocRule.chapterList, !listRule.isEmpty {
                chapterElements = RuleEngine.evaluateRawHTML(
                    rule: listRule, html: html, baseURL: url
                )
            } else {
                chapterElements = [html]
            }

            for elementHTML in chapterElements {
                let name = extractField(
                    tocRule.chapterName, html: elementHTML, baseURL: url
                ) ?? ""
                let chapterUrl = extractField(
                    tocRule.chapterUrl, html: elementHTML, baseURL: url
                ) ?? ""

                if !name.isEmpty || !chapterUrl.isEmpty {
                    allChapters.append(ChapterInfo(
                        name: name.isEmpty ? "Untitled" : name,
                        url: chapterUrl
                    ))
                }
            }

            // Check for next page
            if let nextRule = tocRule.nextTocUrl, !nextRule.isEmpty {
                currentUrlString = RuleEngine.evaluateSingle(
                    rule: nextRule, html: html, baseURL: url
                )
            } else {
                currentUrlString = nil
            }

            pagesFollowed += 1
        }

        return allChapters
    }

    // MARK: - Stage 4: Chapter Content

    /// Extracts the text content of a single chapter.
    /// Checks the chapter cache first; on hit, returns cached content without network.
    /// On miss, fetches via network, applies rules, and caches the result.
    /// Handles pagination via nextContentUrl for multi-page chapters.
    /// Applies replaceRegex cleanup if defined.
    func chapterContent(
        source: BookSourceSnapshot,
        chapterUrl: String,
        progress: (@Sendable (PipelineStage) -> Void)? = nil
    ) async throws -> String {
        try Task.checkCancellation()
        progress?(.content)

        guard let contentRule = source.ruleContent,
              let contentSelector = contentRule.content,
              !contentSelector.isEmpty else {
            throw PipelineError.missingContentRule
        }

        // Check cache first (D06)
        if let cache = chapterCache,
           let cached = await cache.get(
               sourceURL: source.sourceURL, chapterURL: chapterUrl
           ) {
            return cached
        }

        var allText: [String] = []
        var currentUrlString: String? = chapterUrl
        var pagesFollowed = 0

        while let urlStr = currentUrlString,
              pagesFollowed < maxPaginationDepth {
            try Task.checkCancellation()

            let resolved = resolveURL(urlStr, against: source.sourceURL)
            guard let url = URL(string: resolved) else { break }

            let html = try await fetchHTML(url, source.parsedHeaders)

            let texts = RuleEngine.evaluate(
                rule: contentSelector, html: html, baseURL: url
            )
            allText.append(contentsOf: texts)

            // Check for next content page
            if let nextRule = contentRule.nextContentUrl, !nextRule.isEmpty {
                currentUrlString = RuleEngine.evaluateSingle(
                    rule: nextRule, html: html, baseURL: url
                )
            } else {
                currentUrlString = nil
            }

            pagesFollowed += 1
        }

        guard !allText.isEmpty else {
            throw PipelineError.emptyContent
        }

        var result = allText.joined(separator: "\n")

        if let replaceRegex = contentRule.replaceRegex, !replaceRegex.isEmpty {
            result = RegexRuleEvaluator.replace(
                pattern: replaceRegex, replacement: "", in: result
            )
        }

        // Cache the result (D06)
        if let cache = chapterCache {
            await cache.set(
                sourceURL: source.sourceURL,
                chapterURL: chapterUrl,
                content: result
            )
        }

        return result
    }

    // MARK: - Private Helpers

    /// Extracts a single field value using an optional rule string.
    private func extractField(
        _ rule: String?,
        html: String,
        baseURL: URL
    ) -> String? {
        guard let rule, !rule.isEmpty else { return nil }
        return RuleEngine.evaluateSingle(rule: rule, html: html, baseURL: baseURL)
    }

    /// Resolves a potentially relative URL against a base URL string.
    private func resolveURL(
        _ urlString: String,
        against baseURLString: String
    ) -> String {
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return urlString
        }
        if let base = URL(string: baseURLString),
           let resolved = URL(string: urlString, relativeTo: base) {
            return resolved.absoluteString
        }
        return urlString
    }
}
