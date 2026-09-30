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
        chunkerVersion: String = SemanticChunker.chunkerVersion,
        schemaVersion: Int = SemanticIndexMetadata.currentSchemaVersion,
        buildTimestamp: Date = Date(),
        chunkCount: Int
    ) {
        self.bookFingerprintKey = bookFingerprintKey
        self.modelIdentifier = modelIdentifier
        self.embeddingDimension = embeddingDimension
        self.chunkerVersion = chunkerVersion
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
}

struct SemanticChunkMetadata: Codable, Sendable, Equatable, Identifiable {
    var id: String { chunkID }
    let chunkID: String
    let vectorKey: UInt64
    let bookFingerprintKey: String
    let sourceUnitID: String
    let sourceLabel: String?
    let chapterTitle: String?
    let pageIndex: Int?
    let href: String?
    let snippet: String
    let locator: Locator
    let isOCRDerived: Bool
}
