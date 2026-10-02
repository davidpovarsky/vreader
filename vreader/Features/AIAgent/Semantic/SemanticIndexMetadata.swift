// Purpose: Models for semantic index metadata and chunk provenance records.
// Kept in a separate rebuildable store outside the vector ANN index.
// Preserves exact local and global UTF-16 ranges for boundary spoiler safety.

import Foundation

struct SemanticIndexMetadata: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 2

    let bookFingerprintKey: String
    let modelIdentifier: String
    let modelRevision: String?
    let embeddingDimension: Int
    let chunkerVersion: String
    let extractionVersion: Int
    let vectorIndexVersion: Int
    let schemaVersion: Int
    let buildTimestamp: Date
    let chunkCount: Int

    init(
        bookFingerprintKey: String,
        modelIdentifier: String = AISemanticModelManager.modelIdentifier,
        modelRevision: String? = nil,
        embeddingDimension: Int = AISemanticModelManager.embeddingDimension,
        chunkerVersion: Any = SemanticChunker.chunkerVersion,
        extractionVersion: Int = 1,
        vectorIndexVersion: Int = 1,
        schemaVersion: Int = SemanticIndexMetadata.currentSchemaVersion,
        buildTimestamp: Date = Date(),
        chunkCount: Int = 0
    ) {
        self.bookFingerprintKey = bookFingerprintKey
        self.modelIdentifier = modelIdentifier
        self.modelRevision = modelRevision
        self.embeddingDimension = embeddingDimension
        self.chunkerVersion = "\(chunkerVersion)"
        self.extractionVersion = extractionVersion
        self.vectorIndexVersion = vectorIndexVersion
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
    let sourceUnitIndex: Int?
    let sourceLabel: String?
    let chapterTitle: String?
    let pageIndex: Int?
    let href: String?
    let snippet: String
    let locator: Locator
    let localStartUTF16: Int?
    let localEndUTF16: Int?
    let globalStartUTF16: Int?
    let globalEndUTF16: Int?
    let isOCRDerived: Bool

    init(
        chunkID: String,
        vectorKey: UInt64,
        bookFingerprintKey: String,
        bookTitle: String? = nil,
        sourceUnitID: String,
        sourceUnitIndex: Int? = nil,
        sourceLabel: String?,
        chapterTitle: String?,
        pageIndex: Int?,
        href: String?,
        snippet: String,
        locator: Locator,
        localStartUTF16: Int? = nil,
        localEndUTF16: Int? = nil,
        globalStartUTF16: Int? = nil,
        globalEndUTF16: Int? = nil,
        isOCRDerived: Bool
    ) {
        self.chunkID = chunkID
        self.vectorKey = vectorKey
        self.bookFingerprintKey = bookFingerprintKey
        self.bookTitle = bookTitle
        self.sourceUnitID = sourceUnitID
        self.sourceUnitIndex = sourceUnitIndex
        self.sourceLabel = sourceLabel
        self.chapterTitle = chapterTitle
        self.pageIndex = pageIndex
        self.href = href
        self.snippet = snippet
        self.locator = locator
        self.localStartUTF16 = localStartUTF16
        self.localEndUTF16 = localEndUTF16
        self.globalStartUTF16 = globalStartUTF16
        self.globalEndUTF16 = globalEndUTF16
        self.isOCRDerived = isOCRDerived
    }

    init(
        chunkID: String,
        vectorKey: UInt64? = nil,
        bookFingerprintKey: String,
        bookTitle: String? = nil,
        locator: Locator,
        sourceUnitID: String? = nil,
        sourceUnitIndex: Int? = nil,
        sourceLabel: String? = nil,
        chapterTitle: String? = nil,
        pageIndex: Int? = nil,
        href: String? = nil,
        snippet: String,
        localStartUTF16: Int? = nil,
        localEndUTF16: Int? = nil,
        globalStartUTF16: Int? = nil,
        globalEndUTF16: Int? = nil,
        isOCRDerived: Bool = false
    ) {
        self.chunkID = chunkID
        if let vectorKey {
            self.vectorKey = vectorKey
        } else {
            self.vectorKey = SemanticVectorKey.deriveKey(for: chunkID)
        }
        self.bookFingerprintKey = bookFingerprintKey
        self.bookTitle = bookTitle
        self.sourceUnitID = sourceUnitID ?? href ?? chunkID
        self.sourceUnitIndex = sourceUnitIndex
        self.sourceLabel = sourceLabel
        self.chapterTitle = chapterTitle
        self.pageIndex = pageIndex
        self.href = href
        self.snippet = snippet
        self.locator = locator
        self.localStartUTF16 = localStartUTF16
        self.localEndUTF16 = localEndUTF16
        self.globalStartUTF16 = globalStartUTF16
        self.globalEndUTF16 = globalEndUTF16
        self.isOCRDerived = isOCRDerived
    }
}
