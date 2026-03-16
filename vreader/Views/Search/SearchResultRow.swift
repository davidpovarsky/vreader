// Purpose: Row view for displaying a single search result with highlighted snippet.
//
// Key decisions:
// - Uses HighlightedSnippet to bold query matches in the snippet text.
// - Strips FTS5 <b>...</b> markers and applies bold via HighlightedSnippet.
// - Shows source context (chapter, page, section) as secondary text.
// - Accessibility labels for VoiceOver.
//
// @coordinates-with SearchView.swift, SearchResult (SearchService.swift),
//   HighlightedSnippet.swift

import SwiftUI

/// Row view for a single search result.
struct SearchResultRow: View {
    let result: SearchResult
    /// The current search query, used to bold matching terms in the snippet.
    var query: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(HighlightedSnippet.highlight(snippet: result.snippet, query: query))
                .font(.body)
                .lineLimit(3)

            if !result.sourceContext.isEmpty {
                Text(result.sourceContext)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("searchResultRow")
    }

    // MARK: - Private

    private var accessibilityText: String {
        let clean = result.snippet
            .replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")
        if result.sourceContext.isEmpty {
            return clean
        }
        return "\(clean), \(result.sourceContext)"
    }
}
