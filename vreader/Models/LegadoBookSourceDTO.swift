// Purpose: Codable DTO matching Legado's BookSource JSON format exactly.
// Used as an intermediary for import/export — maps to/from VReader's BookSource model.
//
// Key decisions:
// - All fields optional for forward compatibility (unknown fields ignored).
// - Field names match Legado's camelCase JSON keys exactly.
// - Rule sub-objects use separate DTO structs with flexible decoding.
// - lastUpdateTime is Int64 (milliseconds since epoch) in Legado format.
//
// @coordinates-with: LegadoImporter.swift, BookSource.swift, BookSourceRules.swift

import Foundation

/// DTO matching Legado's BookSource JSON format for import/export.
/// Uses flexible decoding: unknown fields are silently ignored.
struct LegadoBookSourceDTO: Codable, Sendable {

    // MARK: - Identity

    var bookSourceUrl: String?
    var bookSourceName: String?
    var bookSourceGroup: String?
    var bookSourceType: Int?
    var enabled: Bool?

    // MARK: - Configuration

    var searchUrl: String?
    var header: String?
    var loginUrl: String?
    var concurrentRate: String?

    // MARK: - Rules

    var ruleSearch: LegadoSearchRuleDTO?
    var ruleBookInfo: LegadoBookInfoRuleDTO?
    var ruleToc: LegadoTocRuleDTO?
    var ruleContent: LegadoContentRuleDTO?

    // MARK: - Metadata

    var lastUpdateTime: Int64?
    var customOrder: Int?
    var weight: Int?
    var bookSourceComment: String?
}

/// Legado search rule DTO — all fields optional, unknown keys ignored.
struct LegadoSearchRuleDTO: Codable, Sendable {
    var bookList: String?
    var name: String?
    var author: String?
    var bookUrl: String?
    var coverUrl: String?
    var kind: String?
    var wordCount: String?
    var intro: String?
    var lastChapter: String?

    /// Collects all non-nil rule strings for compatibility analysis.
    var allRuleStrings: [String] {
        [bookList, name, author, bookUrl, coverUrl,
         kind, wordCount, intro, lastChapter].compactMap { $0 }
    }
}

/// Legado book info rule DTO.
struct LegadoBookInfoRuleDTO: Codable, Sendable {
    var name: String?
    var author: String?
    var intro: String?
    var coverUrl: String?
    var tocUrl: String?
    var kind: String?
    var wordCount: String?
    var lastChapter: String?

    var allRuleStrings: [String] {
        [name, author, intro, coverUrl, tocUrl,
         kind, wordCount, lastChapter].compactMap { $0 }
    }
}

/// Legado TOC rule DTO.
struct LegadoTocRuleDTO: Codable, Sendable {
    var chapterList: String?
    var chapterName: String?
    var chapterUrl: String?
    var nextTocUrl: String?
    var isVip: String?
    var isPay: String?
    var updateTime: String?

    var allRuleStrings: [String] {
        [chapterList, chapterName, chapterUrl, nextTocUrl,
         isVip, isPay, updateTime].compactMap { $0 }
    }
}

/// Legado content rule DTO.
struct LegadoContentRuleDTO: Codable, Sendable {
    var content: String?
    var nextContentUrl: String?
    var replaceRegex: String?
    var webJs: String?
    var sourceRegex: String?

    var allRuleStrings: [String] {
        [content, nextContentUrl, replaceRegex,
         webJs, sourceRegex].compactMap { $0 }
    }
}

// MARK: - Flexible Decoding (ignore unknown keys)

extension LegadoBookSourceDTO {
    /// Custom CodingKeys not needed — Codable already ignores unknown keys
    /// when no explicit CodingKeys enum is provided.
    /// (Swift's default synthesized Codable skips unknown keys.)
}
