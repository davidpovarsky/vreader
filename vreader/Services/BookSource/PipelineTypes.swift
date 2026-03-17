// Purpose: Shared data types for the BookSource scraping pipeline.
// Separated from BookSourcePipeline.swift to keep files under 300 lines.
//
// Key decisions:
// - All types are Sendable for safe use across actor boundaries.
// - BookSourceSnapshot is a value-type mirror of the SwiftData @Model BookSource.
// - PipelineError is Equatable for easy test assertions.
//
// @coordinates-with: BookSourcePipeline.swift, BookSource.swift, BookSourceRules.swift

import Foundation

// MARK: - Pipeline Stage

/// Represents the current stage of the scraping pipeline.
enum PipelineStage: String, Sendable {
    case search
    case bookInfo
    case toc
    case content
}

// MARK: - Pipeline Data Types

/// A single book result from a search query.
struct BookSearchResult: Sendable, Equatable {
    var name: String?
    var author: String?
    var bookUrl: String?
    var coverUrl: String?
}

/// Detailed information about a book.
struct BookDetail: Sendable, Equatable {
    var name: String?
    var author: String?
    var intro: String?
    var coverUrl: String?
    var tocUrl: String?
}

/// A single chapter entry from a table of contents.
struct ChapterInfo: Sendable, Equatable {
    var name: String
    var url: String
}

// MARK: - Pipeline Errors

/// Errors that can occur during pipeline execution.
enum PipelineError: Error, Equatable {
    /// No search rule defined on the source.
    case missingSearchRule
    /// No book info rule defined on the source.
    case missingBookInfoRule
    /// No TOC rule defined on the source.
    case missingTocRule
    /// No content rule defined on the source.
    case missingContentRule
    /// The search URL template is missing from the source.
    case missingSearchURL
    /// The URL string could not be parsed.
    case invalidURL(String)
    /// The fetched content was empty after rule extraction.
    case emptyContent
    /// The pipeline was cancelled.
    case cancelled
    /// A fetch error occurred.
    case fetchFailed(String)
}

// MARK: - Fetch Provider

/// A closure type that fetches HTML from a URL. Abstracted for testability.
/// - Parameters:
///   - url: The URL to fetch.
///   - headers: Optional HTTP headers.
/// - Returns: The HTML string.
typealias HTMLFetchProvider = @Sendable (URL, [String: String]?) async throws -> String

// MARK: - BookSourceSnapshot

/// A Sendable, value-type snapshot of BookSource for use across actor boundaries.
/// BookSource is a SwiftData @Model (reference type, not Sendable), so the pipeline
/// works with this snapshot instead.
struct BookSourceSnapshot: Sendable {
    let sourceURL: String
    let sourceName: String
    let searchURL: String?
    let header: String?
    let ruleSearch: BSSearchRule?
    let ruleBookInfo: BSBookInfoRule?
    let ruleToc: BSTocRule?
    let ruleContent: BSContentRule?

    /// Parses the JSON header string into a dictionary.
    var parsedHeaders: [String: String]? {
        guard let header, !header.isEmpty,
              let data = header.data(using: .utf8),
              let dict = try? JSONDecoder().decode(
                  [String: String].self, from: data
              ) else {
            return nil
        }
        return dict
    }

    /// Creates a snapshot from a BookSource model object.
    /// Call this on the main actor or within a SwiftData context.
    init(from source: BookSource) {
        self.sourceURL = source.sourceURL
        self.sourceName = source.sourceName
        self.searchURL = source.searchURL
        self.header = source.header
        self.ruleSearch = source.ruleSearch
        self.ruleBookInfo = source.ruleBookInfo
        self.ruleToc = source.ruleToc
        self.ruleContent = source.ruleContent
    }

    /// Direct initializer for testing without a SwiftData model.
    init(
        sourceURL: String,
        sourceName: String,
        searchURL: String? = nil,
        header: String? = nil,
        ruleSearch: BSSearchRule? = nil,
        ruleBookInfo: BSBookInfoRule? = nil,
        ruleToc: BSTocRule? = nil,
        ruleContent: BSContentRule? = nil
    ) {
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.searchURL = searchURL
        self.header = header
        self.ruleSearch = ruleSearch
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
    }
}
