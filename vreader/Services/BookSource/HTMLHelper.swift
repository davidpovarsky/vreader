// Purpose: Low-level HTML parsing utilities for the BookSource rule engine.
// Provides attribute extraction, HTML tag stripping, entity decoding,
// URL resolution, and index application.
//
// Key decisions:
// - Enum namespace (stateless, all static).
// - Uses NSRegularExpression (no external dependencies).
// - Supports double-quoted, single-quoted, and unquoted HTML attributes.
// - Decodes the most common HTML entities (not exhaustive).
//
// @coordinates-with: CSSRuleEvaluator.swift, RuleEngine.swift

import Foundation

/// Low-level HTML parsing utilities used by CSSRuleEvaluator.
enum HTMLHelper {

    // MARK: - Attribute Parsing

    /// Parses the value of a named attribute from an HTML attributes string.
    /// Handles `attr="value"`, `attr='value'`, and `attr=value`.
    static func parseAttribute(named name: String, from attrs: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\\b\(escaped)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ),
              let match = regex.firstMatch(
                in: attrs, range: NSRange(attrs.startIndex..., in: attrs)
              )
        else { return nil }

        for g in 1...3 {
            if g < match.numberOfRanges,
               match.range(at: g).location != NSNotFound,
               let r = Range(match.range(at: g), in: attrs) {
                return String(attrs[r])
            }
        }
        return nil
    }

    /// Parses the class attribute and returns individual class names.
    static func parseClasses(from attrs: String) -> Set<String> {
        guard let cls = parseAttribute(named: "class", from: attrs) else {
            return []
        }
        return Set(
            cls.split(separator: " ", omittingEmptySubsequences: true)
               .map(String.init)
        )
    }

    // MARK: - HTML Tag Stripping

    /// Removes HTML tags from a string, returning plain text with decoded entities.
    static func stripHTMLTags(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "<[^>]+>", options: []
        ) else { return html }

        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        let stripped = regex.stringByReplacingMatches(
            in: html, range: range, withTemplate: ""
        )
        return decodeHTMLEntities(stripped)
    }

    /// Decodes common HTML entities to their character equivalents.
    static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
            ("&nbsp;", " "),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    // MARK: - URL Resolution

    /// Resolves a URL value against a base URL for href/src-type attributes.
    /// Returns the original value if the attribute is not URL-typed or already absolute.
    static func resolveURL(
        _ value: String,
        attribute: String,
        baseURL: URL?
    ) -> String {
        let urlAttrs: Set<String> = ["href", "src", "action", "data"]
        guard urlAttrs.contains(attribute.lowercased()),
              let base = baseURL, !value.isEmpty else {
            return value
        }

        if value.hasPrefix("http://") || value.hasPrefix("https://")
            || value.hasPrefix("//") {
            return value
        }

        if let resolved = URL(string: value, relativeTo: base) {
            return resolved.absoluteString
        }
        return value
    }

    // MARK: - Index Application

    /// Applies index selection to a results array.
    /// Negative indices count from the end (-1 = last element).
    static func applyIndex(results: [String], index: Int?) -> [String] {
        guard let idx = index else { return results }
        guard !results.isEmpty else { return [] }

        let resolved = idx < 0 ? results.count + idx : idx
        guard resolved >= 0, resolved < results.count else { return [] }
        return [results[resolved]]
    }

    // MARK: - NSTextCheckingResult Helper

    /// Safely extracts a capture group substring from a regex match.
    static func safeSubstring(
        _ nsString: NSString,
        match: NSTextCheckingResult,
        group: Int
    ) -> String {
        guard group < match.numberOfRanges,
              match.range(at: group).location != NSNotFound else {
            return ""
        }
        return nsString.substring(with: match.range(at: group))
    }
}
