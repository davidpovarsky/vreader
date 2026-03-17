// Purpose: Main dispatcher for BookSource rule evaluation.
// Auto-detects rule type (CSS/regex/XPath) and delegates to the appropriate evaluator.
//
// Key decisions:
// - Enum namespace (stateless, all static).
// - XPath rules are detected but return empty (deferred to D08).
// - Empty/whitespace rules return empty arrays (not errors).
// - evaluateSingle convenience for single-value extraction.
//
// @coordinates-with: LegadoRuleParser.swift, CSSRuleEvaluator.swift,
//   RegexRuleEvaluator.swift, BookSourcePipeline.swift

import Foundation

/// Main dispatcher for evaluating BookSource rules against HTML content.
///
/// Supports:
/// - CSS selectors with Legado syntax (`selector@attribute!index`)
/// - Regex extraction (`:regex:pattern`)
/// - XPath detection (deferred to D08, returns empty)
enum RuleEngine {

    // MARK: - Evaluate (Multiple Results)

    /// Evaluates a rule against HTML and returns all matching values.
    ///
    /// Rule type is auto-detected:
    /// - `:regex:` prefix -> regex extraction
    /// - `//` or `/` prefix -> XPath (deferred, returns empty)
    /// - Otherwise -> CSS selector with optional Legado operators (@, !)
    ///
    /// - Parameters:
    ///   - rule: The rule string (CSS selector, regex, or XPath).
    ///   - html: The HTML content to evaluate against.
    ///   - baseURL: Base URL for resolving relative URLs.
    /// - Returns: Array of extracted strings. Empty if no matches.
    static func evaluate(rule: String, html: String, baseURL: URL?) -> [String] {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let parsed = LegadoRuleParser.parse(trimmed)

        switch parsed.type {
        case .css:
            return CSSRuleEvaluator.evaluate(
                selector: parsed.selector,
                attribute: parsed.attribute,
                index: parsed.index,
                html: html,
                baseURL: baseURL
            )

        case .regex:
            guard let pattern = parsed.regexPattern, !pattern.isEmpty else {
                return []
            }
            return RegexRuleEvaluator.extract(pattern: pattern, from: html)

        case .xpath:
            // XPath deferred to D08
            return []
        }
    }

    // MARK: - Evaluate (Single Result)

    /// Evaluates a rule and returns only the first matching value.
    ///
    /// Convenience for fields that expect a single value (e.g., book title).
    ///
    /// - Parameters:
    ///   - rule: The rule string.
    ///   - html: The HTML content to evaluate against.
    ///   - baseURL: Base URL for resolving relative URLs.
    /// - Returns: First matching value, or nil if no matches.
    static func evaluateSingle(
        rule: String,
        html: String,
        baseURL: URL?
    ) -> String? {
        evaluate(rule: rule, html: html, baseURL: baseURL).first
    }

    // MARK: - Evaluate Raw HTML (Container Extraction)

    /// Evaluates a CSS rule and returns the full HTML of each matched element.
    ///
    /// Used by the pipeline for container rules (e.g., bookList, chapterList)
    /// where sub-rules need to be applied against each element's HTML.
    /// Regex and XPath rules fall back to normal `evaluate`.
    ///
    /// - Parameters:
    ///   - rule: The CSS selector rule string.
    ///   - html: The HTML content to evaluate against.
    ///   - baseURL: Base URL for resolving relative URLs.
    /// - Returns: Array of raw HTML strings for each matched element.
    static func evaluateRawHTML(
        rule: String,
        html: String,
        baseURL: URL?
    ) -> [String] {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let parsed = LegadoRuleParser.parse(trimmed)

        switch parsed.type {
        case .css:
            return CSSRuleEvaluator.evaluateRawHTML(
                selector: parsed.selector,
                index: parsed.index,
                html: html
            )
        case .regex, .xpath:
            return evaluate(rule: rule, html: html, baseURL: baseURL)
        }
    }
}
