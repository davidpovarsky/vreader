// Purpose: Models for semantic index metadata and chunk provenance records.
// Kept in a separate rebuildable store outside the vector ANN index.

import Foundation

struct SemanticIndexMetadata: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    let bookFingerprintKey: String
    let modelIdentifier: String
    let embeddingDimension: Int
    let chunkerVersion: String
    let schemaVersion: Int
    let buildTimestamp: Date
    let chunkCount: Int

    init(
        bookFingerprintKey: String,
        modelIdentifier: String = AISemanticModelManager.modelIdentifier,
        embeddingDimension: Int = AISemanticModelManager.embeddingDimension,
        chunkerVersion: Any = SemanticChunker.chunkerVersion,
        extractionVersion: Int = 1,
        schemaVersion: Int = SemanticIndexMetadata.currentSchemaVersion,
        buildTimestamp: Date = Date(),
        chunkCount: Int = 0
    ) {
        self.bookFingerprintKey = bookFingerprintKey
        self.modelIdentifier = modelIdentifier
        self.embeddingDimension = embeddingDimension
        self.chunkerVersion = "\(chunkerVersion)"
        self.schemaVersion = schemaVersion
        self.buildTimestamp = buildTimestamp
        self.chunkCount = chunkCount
    }

    /// Validates if this metadata matches current active configurations.
    func isCompatible(withActiveModel model: String, dimension: Int) -> Bool {
        return schemaVersion == Self.currentSchemaVersion &&
               chunkerVersion == SemanticChunker.chunkerVersion &&
               modelIdentifier == model &&
               embeddingDimension == dimension
    }

    /// Validates compatibility between two metadata snapshots.
    func isCompatible(with other: SemanticIndexMetadata) -> Bool {
        return schemaVersion == other.schemaVersion &&
               chunkerVersion == other.chunkerVersion &&
               embeddingDimension == other.embeddingDimension
    }
}

struct SemanticChunkMetadata: Codable, Sendable, Equatable, Identifiable {
    var id: String { chunkID }
    let chunkID: String
    let vectorKey: UInt64
    let bookFingerprintKey: String
    let bookTitle: String?
    let sourceUnitID: String
    let sourceLabel: String?
    let chapterTitle: String?
    let pageIndex: Int?
    let href: String?
    let snippet: String
    let locator: Locator
    let isOCRDerived: Bool

    init(
        chunkID: String,
        vectorKey: UInt64? = nil,
        bookFingerprintKey: String,
        bookTitle: String? = nil,
        locator: Locator,
        sourceUnitID: String? = nil,
        sourceLabel: String? = nil,
        chapterTitle: String? = nil,
        pageIndex: Int? = nil,
        href: String? = nil,
        snippet: String,
        charRange: Range<Int>? = nil,
        isOCRDerived: Bool = false
    ) {
        self.chunkID = chunkID
        if let vectorKey {
            self.vectorKey = vectorKey
        } else {
            var hasher = Hasher()
            hasher.combine(chunkID)
            self.vectorKey = UInt64(bitPattern: Int64(hasher.finalize()))
        }
        self.bookFingerprintKey = bookFingerprintKey
        self.bookTitle = bookTitle
        self.sourceUnitID = sourceUnitID ?? href ?? chunkID
        self.sourceLabel = sourceLabel
        self.chapterTitle = chapterTitle
        self.pageIndex = pageIndex
        self.href = href
        self.snippet = snippet
        self.locator = locator
        self.isOCRDerived = isOCRDerived
    }
}
