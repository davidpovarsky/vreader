// Purpose: Bridges VReader's search UI and Foliate-js built-in search.
// Generates JS strings for search operations and parses search result messages.
// Pure functions only — no WKWebView dependency.
//
// Key decisions:
// - JS generation escapes query/CFI strings for safe embedding in evaluateJavaScript calls.
// - Excerpt parsing handles both Foliate-js object format {pre, match, post} and plain strings.
// - Grouped results (book-wide search) are flattened into individual FoliateSearchResult items.
//
// @coordinates-with: FoliateTypes.swift, FoliateViewCoordinator.swift, foliate-host.js

import Foundation

enum FoliateSearchAdapter {

    /// Generate JS to start a Foliate-js search.
    /// Calls `readerAPI.search({query: "..."})` with the query properly escaped.
    static func searchJS(query: String) -> String {
        let escaped = FoliateJSEscaper.escapeForJSString(query)
        return "readerAPI.search({query: '\(escaped)'})"
    }

    /// Generate JS to clear search highlights.
    static func clearSearchJS() -> String {
        "readerAPI.clearSearch()"
    }

    /// Generate JS to navigate to a search result by CFI.
    static func goToResultJS(cfi: String) -> String {
        let escaped = FoliateJSEscaper.escapeForJSString(cfi)
        return "readerAPI.goTo('\(escaped)')"
    }

    /// Parse a direct search result from a `search-result` JS message body.
    /// Handles two excerpt formats:
    /// - Object: `{pre: String, match: String, post: String}` (standard Foliate-js)
    /// - String: plain text (fallback)
    /// Returns nil if required fields (cfi, excerpt) are missing.
    static func parseSearchResult(_ body: Any) -> FoliateSearchResult? {
        guard let dict = body as? [String: Any] else { return nil }
        guard let cfi = dict["cfi"] as? String else { return nil }
        guard let excerpt = parseExcerpt(dict["excerpt"]) else { return nil }

        let sectionLabel = dict["sectionLabel"] as? String

        return FoliateSearchResult(cfi: cfi, excerpt: excerpt, sectionLabel: sectionLabel)
    }

    /// Parse a grouped search result from a book-wide `search-result` JS message body.
    /// Format: `{label: String?, subitems: [{cfi, excerpt}]}`.
    /// Each subitem is parsed and tagged with the section label.
    /// Returns empty array if the body is invalid or has no valid subitems.
    static func parseGroupedSearchResults(_ body: Any) -> [FoliateSearchResult] {
        guard let dict = body as? [String: Any] else { return [] }
        guard let subitems = dict["subitems"] as? [[String: Any]] else { return [] }

        let label = dict["label"] as? String

        return subitems.compactMap { item in
            guard let cfi = item["cfi"] as? String else { return nil }
            guard let excerpt = parseExcerpt(item["excerpt"]) else { return nil }
            return FoliateSearchResult(cfi: cfi, excerpt: excerpt, sectionLabel: label)
        }
    }

    // MARK: - Private

    /// Parse an excerpt value that may be a Foliate-js object `{pre, match, post}` or a plain string.
    /// Returns nil if the value is neither format or if `match` is missing from an object excerpt.
    private static func parseExcerpt(_ value: Any?) -> String? {
        if let dict = value as? [String: Any] {
            guard let match = dict["match"] as? String else { return nil }
            let pre = dict["pre"] as? String ?? ""
            let post = dict["post"] as? String ?? ""
            return pre + match + post
        }
        return value as? String
    }

}
