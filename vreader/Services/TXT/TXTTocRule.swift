// Purpose: Model for TXT table-of-contents detection rules.
// Ported from Legado's txtTocRule.json (25 battle-tested patterns).
//
// Key decisions:
// - Codable for future persistence (user-customizable rules).
// - Sendable for safe cross-actor use.
// - Identifiable by integer ID matching Legado's numbering scheme.
// - `enabled` is mutable so users can toggle rules on/off.
//
// @coordinates-with: TXTTocRuleEngine.swift, TOCBuilder.swift

import Foundation

/// A single TXT chapter detection rule with a regex pattern.
struct TXTTocRule: Codable, Sendable, Identifiable {
    /// Unique identifier (matches Legado numbering).
    let id: Int
    /// Whether this rule is active for auto-detection.
    var enabled: Bool
    /// Human-readable name describing what this rule matches.
    let name: String
    /// Regex pattern string (applied with .anchorsMatchLines option).
    let rule: String
    /// Example text that matches this rule.
    let example: String
    /// Original serial number from Legado (for ordering).
    let serialNumber: Int
}
