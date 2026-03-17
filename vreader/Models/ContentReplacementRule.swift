// Purpose: SwiftData model for content replacement rules.
// Users can define string or regex find/replace rules to fix OCR errors,
// remove watermarks, or customize display text.
//
// Key decisions:
// - SwiftData @Model for persistence.
// - isRegex flag distinguishes plain string vs regex patterns.
// - scope: .global applies to all books, .perBook(fingerprint) to one.
// - order: lower number = applied first.
// - enabled: toggle without deleting.
//
// @coordinates-with: ReplacementTransform.swift, ReplacementRulesView.swift

import Foundation
import SwiftData

@Model
final class ContentReplacementRule {
    @Attribute(.unique) var ruleId: UUID

    /// The search pattern (plain string or regex).
    var pattern: String

    /// The replacement string. Supports regex group references ($1, $2) when isRegex.
    var replacement: String

    /// Whether the pattern is a regular expression.
    var isRegex: Bool

    /// Scope: empty string = global, non-empty = book fingerprint key.
    var scopeKey: String

    /// Whether this rule is active.
    var enabled: Bool

    /// Sort order — lower runs first.
    var order: Int

    /// User-visible label/note.
    var label: String

    /// Creation date.
    var createdAt: Date

    init(
        ruleId: UUID = UUID(),
        pattern: String,
        replacement: String,
        isRegex: Bool = false,
        scopeKey: String = "",
        enabled: Bool = true,
        order: Int = 0,
        label: String = "",
        createdAt: Date = Date()
    ) {
        self.ruleId = ruleId
        self.pattern = pattern
        self.replacement = replacement
        self.isRegex = isRegex
        self.scopeKey = scopeKey
        self.enabled = enabled
        self.order = order
        self.label = label
        self.createdAt = createdAt
    }
}

// MARK: - Scope Helpers

extension ContentReplacementRule {
    /// Whether this is a global rule (applies to all books).
    var isGlobal: Bool { scopeKey.isEmpty }

    /// Whether this rule applies to a given book fingerprint key.
    func appliesTo(bookKey: String) -> Bool {
        isGlobal || scopeKey == bookKey
    }
}
