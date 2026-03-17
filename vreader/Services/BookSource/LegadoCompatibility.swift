// Purpose: Compatibility classification for Legado book sources.
// Scans rule strings to determine if a source uses CSS-only (Full),
// XPath (Limited), or JavaScript (Unsupported) extraction rules.
//
// @coordinates-with: LegadoImporter.swift, LegadoBookSourceDTO.swift

import Foundation

extension LegadoImporter {

    // MARK: - Compatibility Classification

    /// Classifies a source's rule compatibility level by scanning all rule strings.
    /// - "Unsupported" if any rule uses `<js>` or `{{` (JavaScript execution).
    /// - "Limited" if any rule uses `//` prefix (XPath).
    /// - "Full" if all rules are CSS selectors / regex only.
    static func classifyCompatibility(
        _ dto: LegadoBookSourceDTO
    ) -> String {
        let allRules = collectAllRuleStrings(dto)

        // Empty rules = Full (nothing incompatible)
        guard !allRules.isEmpty else { return "Full" }

        var hasXPath = false

        for rule in allRules {
            // Check for JS execution markers
            if containsJSMarkers(rule) {
                return "Unsupported" // worst case, return immediately
            }
            // Check for XPath
            if containsXPathMarkers(rule) {
                hasXPath = true
            }
        }

        return hasXPath ? "Limited" : "Full"
    }

    /// Collects all rule strings from all rule sections of a DTO.
    static func collectAllRuleStrings(
        _ dto: LegadoBookSourceDTO
    ) -> [String] {
        var strings: [String] = []
        if let r = dto.ruleSearch { strings.append(contentsOf: r.allRuleStrings) }
        if let r = dto.ruleBookInfo { strings.append(contentsOf: r.allRuleStrings) }
        if let r = dto.ruleToc { strings.append(contentsOf: r.allRuleStrings) }
        if let r = dto.ruleContent { strings.append(contentsOf: r.allRuleStrings) }
        return strings
    }

    /// Checks if a rule string contains JavaScript execution markers.
    static func containsJSMarkers(_ rule: String) -> Bool {
        rule.contains("<js>") || rule.contains("{{")
    }

    /// Checks if a rule string contains XPath markers.
    static func containsXPathMarkers(_ rule: String) -> Bool {
        rule.hasPrefix("//")
    }
}
