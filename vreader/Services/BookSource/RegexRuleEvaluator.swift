// Purpose: Evaluates regex rules against text content.
// Supports capture group extraction and pattern replacement.
//
// Key decisions:
// - Enum namespace (no instances needed, all static).
// - If the pattern has capture groups, returns the first group match.
// - If no capture groups, returns the full match.
// - Returns all matches (not just the first).
// - Replacement is a separate method for content cleanup pipelines.
//
// @coordinates-with: RuleEngine.swift, LegadoRuleParser.swift

import Foundation

/// Evaluates regex patterns against text content.
enum RegexRuleEvaluator {

    // MARK: - Extract

    /// Extracts matches from text using a regex pattern.
    ///
    /// If the pattern contains capture groups, returns the first capture group
    /// from each match. If no capture groups, returns the full match text.
    ///
    /// - Parameters:
    ///   - pattern: The regex pattern string.
    ///   - text: The text to search.
    /// - Returns: Array of matched strings. Empty if no matches or invalid pattern.
    static func extract(pattern: String, from text: String) -> [String] {
        guard !pattern.isEmpty, !text.isEmpty else { return [] }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: range)

        guard !matches.isEmpty else { return [] }

        let hasGroups = regex.numberOfCaptureGroups > 0

        return matches.compactMap { match in
            if hasGroups && match.numberOfRanges > 1 {
                let groupRange = match.range(at: 1)
                guard groupRange.location != NSNotFound else { return nil }
                return nsText.substring(with: groupRange)
            } else {
                let matchRange = match.range(at: 0)
                guard matchRange.location != NSNotFound else { return nil }
                return nsText.substring(with: matchRange)
            }
        }
    }

    // MARK: - Replace

    /// Replaces all occurrences of a regex pattern in the input string.
    ///
    /// - Parameters:
    ///   - pattern: The regex pattern to match.
    ///   - replacement: The replacement string.
    ///   - input: The string to modify.
    /// - Returns: The modified string, or the original if the pattern is invalid.
    static func replace(pattern: String, replacement: String, in input: String) -> String {
        guard !pattern.isEmpty else { return input }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }

        let nsInput = input as NSString
        let range = NSRange(location: 0, length: nsInput.length)
        return regex.stringByReplacingMatches(
            in: input,
            range: range,
            withTemplate: replacement
        )
    }
}
