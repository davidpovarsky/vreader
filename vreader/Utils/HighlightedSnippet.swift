// Purpose: Pure function that highlights query matches in a snippet string
// by applying bold styling to matched portions via AttributedString.
//
// Key decisions:
// - Case-insensitive matching.
// - Regex special characters in query are escaped (literal matching).
// - FTS5 <b>...</b> tags stripped before highlighting.
// - Returns plain AttributedString when query is empty or has no matches.
//
// @coordinates-with SearchResultRow.swift

import Foundation
import SwiftUI

/// Highlights query matches within a snippet using bold AttributedString runs.
enum HighlightedSnippet {

    /// Returns an `AttributedString` with all occurrences of `query` in `snippet` bolded.
    static func highlight(
        snippet: String,
        query: String,
        baseFont: Font = .body
    ) -> AttributedString {
        let cleaned = snippet
            .replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty, !cleaned.isEmpty else {
            return AttributedString(cleaned)
        }

        let escaped = NSRegularExpression.escapedPattern(for: trimmedQuery)

        guard let regex = try? NSRegularExpression(
            pattern: escaped,
            options: .caseInsensitive
        ) else {
            return AttributedString(cleaned)
        }

        let nsRange = NSRange(cleaned.startIndex..., in: cleaned)
        let matches = regex.matches(in: cleaned, range: nsRange)

        guard !matches.isEmpty else {
            return AttributedString(cleaned)
        }

        var result = AttributedString()
        var currentIndex = cleaned.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: cleaned) else { continue }

            if currentIndex < matchRange.lowerBound {
                let before = String(cleaned[currentIndex..<matchRange.lowerBound])
                result.append(AttributedString(before))
            }

            let matchedText = String(cleaned[matchRange])
            var boldAttr = AttributedString(matchedText)
            boldAttr.font = baseFont.bold()
            result.append(boldAttr)

            currentIndex = matchRange.upperBound
        }

        if currentIndex < cleaned.endIndex {
            let remaining = String(cleaned[currentIndex...])
            result.append(AttributedString(remaining))
        }

        return result
    }
}
