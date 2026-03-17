// Purpose: Parses Legado rule syntax strings into structured components.
// Handles CSS selectors with Legado-specific operators (@, !) and detects
// rule types (CSS, regex, XPath).
//
// Key decisions:
// - Enum namespace (no instances needed, all static).
// - @ splits selector from attribute name.
// - ! splits from index (0-based, negative for from-end).
// - :regex: prefix triggers regex mode.
// - /... or //... prefix triggers xpath detection (deferred to D08).
//
// @coordinates-with: RuleEngine.swift, CSSRuleEvaluator.swift, RegexRuleEvaluator.swift

import Foundation

/// The type of rule extraction to perform.
enum RuleType: Equatable, Sendable {
    /// CSS selector-based extraction (default).
    case css
    /// Regular expression extraction (prefixed with `:regex:`).
    case regex
    /// XPath extraction (prefixed with `/` or `//`). Deferred to D08.
    case xpath
}

/// Result of parsing a Legado rule string.
struct ParsedRule: Equatable, Sendable {
    /// The detected rule type.
    let type: RuleType
    /// CSS selector string (for CSS rules). Empty if not applicable.
    let selector: String
    /// Attribute to extract (e.g., "href" from `a@href`). Nil = extract text content.
    let attribute: String?
    /// Index to select from matches (e.g., 0 from `li!0`). Nil = all matches.
    let index: Int?
    /// Regex pattern (for regex rules). Nil if not a regex rule.
    let regexPattern: String?
}

/// Parses Legado-format rule strings into structured components.
///
/// Legado rule syntax:
/// - `selector@attribute!index` -- CSS with attribute and index operators
/// - `:regex:pattern` -- regex extraction
/// - `//xpath` or `/xpath` -- XPath (detected but deferred)
enum LegadoRuleParser {

    // MARK: - Parse

    /// Parses a raw rule string into a structured `ParsedRule`.
    ///
    /// Examples:
    /// - `"a@href"` -> CSS, selector="a", attribute="href"
    /// - `"li!0"` -> CSS, selector="li", index=0
    /// - `"a@href!1"` -> CSS, selector="a", attribute="href", index=1
    /// - `":regex:<title>([^<]+)</title>"` -> regex, pattern=`<title>([^<]+)</title>`
    /// - `"//div[@class='result']"` -> xpath (deferred)
    static func parse(_ rule: String) -> ParsedRule {
        let trimmed = rule.trimmingCharacters(in: .whitespaces)

        // Detect regex
        if trimmed.hasPrefix(":regex:") {
            let pattern = String(trimmed.dropFirst(7))
            return ParsedRule(
                type: .regex,
                selector: "",
                attribute: nil,
                index: nil,
                regexPattern: pattern
            )
        }

        // Detect XPath
        if trimmed.hasPrefix("//") || (trimmed.hasPrefix("/") && !trimmed.isEmpty) {
            return ParsedRule(
                type: .xpath,
                selector: trimmed,
                attribute: nil,
                index: nil,
                regexPattern: nil
            )
        }

        // CSS with Legado operators
        return parseCSS(trimmed)
    }

    // MARK: - Private: CSS Parsing

    /// Parses a CSS selector with optional `@attribute` and `!index` operators.
    ///
    /// Parse order: extract `!index` from the end first, then `@attribute`,
    /// leaving the selector as the remainder.
    private static func parseCSS(_ rule: String) -> ParsedRule {
        var remaining = rule
        var index: Int?
        var attribute: String?

        // Extract !index from the end
        if let bangRange = findBangIndex(in: remaining) {
            let indexStr = String(remaining[bangRange.upperBound...])
            if let parsed = Int(indexStr) {
                index = parsed
                remaining = String(remaining[..<bangRange.lowerBound])
            }
        }

        // Extract @attribute
        if let atIndex = findAtOperator(in: remaining) {
            attribute = String(remaining[remaining.index(after: atIndex)...])
            remaining = String(remaining[..<atIndex])
        }

        return ParsedRule(
            type: .css,
            selector: remaining,
            attribute: attribute,
            index: index,
            regexPattern: nil
        )
    }

    /// Finds the position of the `!` operator for index selection.
    /// Only matches `!` followed by an optional `-` and digits at the end.
    private static func findBangIndex(in text: String) -> Range<String.Index>? {
        guard let bangIdx = text.lastIndex(of: "!") else { return nil }
        let after = String(text[text.index(after: bangIdx)...])
        guard Int(after) != nil else { return nil }
        return bangIdx..<text.index(after: bangIdx)
    }

    /// Finds the position of the `@` operator for attribute access.
    /// The `@` must be followed by a valid attribute name (letters, hyphens, underscores).
    private static func findAtOperator(in text: String) -> String.Index? {
        guard let atIdx = text.lastIndex(of: "@") else { return nil }
        let after = String(text[text.index(after: atIdx)...])
        guard !after.isEmpty,
              after.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "_" }) else {
            return nil
        }
        return atIdx
    }
}
