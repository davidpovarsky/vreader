// Purpose: SwiftData model for a web content source with configurable extraction rules.
// Compatible with Legado's BookSource JSON format for import/export.
//
// Key decisions:
// - sourceURL is the unique key (@Attribute(.unique)), matching Legado's bookSourceUrl PK.
// - Rules are stored as Data? (JSON blobs) with computed properties for typed access,
//   following the same safe pattern as Highlight.anchorData. This avoids SwiftData
//   Codable enum decode crashes on schema evolution.
// - sourceType uses Int (0=text, 1=audio, 2=image, 3=file) matching Legado convention.
// - No built-in sources — all user-imported.
//
// @coordinates-with: BookSourceRules.swift, BookSourceListView.swift,
//   BookSourceEditorView.swift, LegadoImporter.swift (future)

import Foundation
import SwiftData

@Model
final class BookSource {
    // MARK: - Identity

    /// Unique source identifier — the base URL of the content source.
    @Attribute(.unique) var sourceURL: String

    /// Human-readable display name for the source.
    var sourceName: String

    /// Optional grouping label for organizing sources.
    var sourceGroup: String?

    /// Source content type: 0=text, 1=audio, 2=image, 3=file.
    var sourceType: Int

    /// Whether this source is active for searches.
    var enabled: Bool

    // MARK: - Configuration

    /// URL template for search. Uses `{{key}}` as keyword placeholder.
    var searchURL: String?

    /// JSON string for custom HTTP headers (User-Agent, Cookie, etc.).
    var header: String?

    // MARK: - Rule Data (JSON blobs)

    /// Raw JSON bytes for search extraction rules.
    var ruleSearchData: Data?

    /// Raw JSON bytes for book info extraction rules.
    var ruleBookInfoData: Data?

    /// Raw JSON bytes for TOC extraction rules.
    var ruleTocData: Data?

    /// Raw JSON bytes for content extraction rules.
    var ruleContentData: Data?

    // MARK: - Metadata

    /// When this source was last updated (import or edit).
    var lastUpdateTime: Date?

    /// User-defined ordering position.
    var customOrder: Int

    // MARK: - Computed Rule Accessors

    /// Decoded search rule. Returns nil when data is missing, empty, or corrupted.
    @Transient var ruleSearch: BSSearchRule? {
        decodeRule(ruleSearchData)
    }

    /// Decoded book info rule. Returns nil when data is missing, empty, or corrupted.
    @Transient var ruleBookInfo: BSBookInfoRule? {
        decodeRule(ruleBookInfoData)
    }

    /// Decoded TOC rule. Returns nil when data is missing, empty, or corrupted.
    @Transient var ruleToc: BSTocRule? {
        decodeRule(ruleTocData)
    }

    /// Decoded content rule. Returns nil when data is missing, empty, or corrupted.
    @Transient var ruleContent: BSContentRule? {
        decodeRule(ruleContentData)
    }

    // MARK: - Init

    init(
        sourceURL: String,
        sourceName: String,
        sourceGroup: String? = nil,
        sourceType: Int = 0,
        enabled: Bool = true,
        searchURL: String? = nil,
        header: String? = nil,
        customOrder: Int = 0
    ) {
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.sourceGroup = sourceGroup
        self.sourceType = sourceType
        self.enabled = enabled
        self.searchURL = searchURL
        self.header = header
        self.customOrder = customOrder
    }

    // MARK: - Rule Update Methods

    /// Updates the search rule. Encodes to JSON bytes for safe SwiftData storage.
    func updateSearchRule(_ rule: BSSearchRule?) {
        ruleSearchData = encodeRule(rule)
    }

    /// Updates the book info rule.
    func updateBookInfoRule(_ rule: BSBookInfoRule?) {
        ruleBookInfoData = encodeRule(rule)
    }

    /// Updates the TOC rule.
    func updateTocRule(_ rule: BSTocRule?) {
        ruleTocData = encodeRule(rule)
    }

    /// Updates the content rule.
    func updateContentRule(_ rule: BSContentRule?) {
        ruleContentData = encodeRule(rule)
    }

    // MARK: - Validation

    /// Validates that a source URL is non-empty and non-whitespace.
    static func validateSourceURL(_ url: String) -> Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Private Helpers

    private func decodeRule<T: Decodable>(_ data: Data?) -> T? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encodeRule<T: Encodable>(_ rule: T?) -> Data? {
        guard let rule else { return nil }
        return try? JSONEncoder().encode(rule)
    }
}
