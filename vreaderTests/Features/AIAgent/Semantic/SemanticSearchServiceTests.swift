// Purpose: Unit tests for SemanticSearchService.
// Tests query embedding, boundary filtering, Hebrew retrieval, and source mapping.

import Testing
import Foundation
@testable import vreader

@Suite("SemanticSearchServiceTests")
struct SemanticSearchServiceTests {

    @Test func searchCurrentBookEnforcesSpoilerBoundaryWhenNotAllowed() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metadataStore = SemanticIndexMetadataStore(storageDirectory: tempDir)
        let indexStore = SemanticIndexStore(dimension: 384, indexDirectory: tempDir)
        let mockEmbedding = MockSemanticEmbeddingService()
        let service = SemanticSearchService(
            embeddingService: mockEmbedding,
            metadataStore: metadataStore,
            indexStore: indexStore
        )

        let bookKey = "book-current"
        let safeLocator = Locator(href: "ch1.xhtml", type: "application/xhtml+xml", title: "Chapter 1")
        let spoilerLocator = Locator(href: "ch10.xhtml", type: "application/xhtml+xml", title: "Chapter 10")

        let safeMeta = SemanticChunkMetadata(
            chunkID: "chunk_safe",
            bookFingerprintKey: bookKey,
            bookTitle: "Mystery Book",
            locator: safeLocator,
            sourceLabel: "Ch. 1",
            chapterTitle: "Chapter 1",
            pageIndex: nil,
            href: "ch1.xhtml",
            snippet: "Early clue in the drawing room.",
            charRange: 0..<50,
            isOCRDerived: false
        )

        let spoilerMeta = SemanticChunkMetadata(
            chunkID: "chunk_spoiler",
            bookFingerprintKey: bookKey,
            bookTitle: "Mystery Book",
            locator: spoilerLocator,
            sourceLabel: "Ch. 10",
            chapterTitle: "Chapter 10",
            pageIndex: nil,
            href: "ch10.xhtml",
            snippet: "The butler did it all along!",
            charRange: 0..<50,
            isOCRDerived: false
        )

        try await metadataStore.saveChunkMetadata([safeMeta, spoilerMeta], for: bookKey)

        let queryVec = try await mockEmbedding.embedQuery("who did it")
        try await indexStore.add(chunkID: "chunk_safe", vector: queryVec, bookFingerprintKey: bookKey)
        try await indexStore.add(chunkID: "chunk_spoiler", vector: queryVec, bookFingerprintKey: bookKey)

        let boundary = AIReadSoFarBoundary(
            locator: safeLocator,
            progression: 0.1,
            chapterIndex: 0,
            pageIndex: nil
        )

        // When read ahead is NOT allowed: only safe chunk is returned
        let safeHits = try await service.searchCurrentBook(
            query: "who did it",
            bookFingerprintKey: bookKey,
            boundary: boundary,
            readAheadAllowed: false,
            maxHits: 5
        )

        #expect(safeHits.count == 1)
        #expect(safeHits[0].chunkID == "chunk_safe")
        #expect(!safeHits[0].aheadOfReader)

        // When read ahead IS allowed: spoiler chunk can be returned and flagged aheadOfReader
        let allHits = try await service.searchCurrentBook(
            query: "who did it",
            bookFingerprintKey: bookKey,
            boundary: boundary,
            readAheadAllowed: true,
            maxHits: 5
        )

        #expect(allHits.count == 2)
        let spoilerHit = allHits.first { $0.chunkID == "chunk_spoiler" }
        #expect(spoilerHit != nil)
        #expect(spoilerHit?.aheadOfReader == true)
    }

    @Test func hebrewSemanticSearchRetrieval() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metadataStore = SemanticIndexMetadataStore(storageDirectory: tempDir)
        let indexStore = SemanticIndexStore(dimension: 384, indexDirectory: tempDir)
        let mockEmbedding = MockSemanticEmbeddingService()
        let service = SemanticSearchService(
            embeddingService: mockEmbedding,
            metadataStore: metadataStore,
            indexStore: indexStore
        )

        let bookKey = "hebrew-book"
        let locator = Locator(href: "shabbat.xhtml", type: "application/xhtml+xml", title: "שבת")
        let meta = SemanticChunkMetadata(
            chunkID: "hebrew_chunk_1",
            bookFingerprintKey: bookKey,
            bookTitle: "ספר ההלכה",
            locator: locator,
            sourceLabel: "הלכות שבת",
            chapterTitle: "שבת",
            pageIndex: nil,
            href: "shabbat.xhtml",
            snippet: "הדלקת נרות שבת קודש בזמן",
            charRange: 0..<50,
            isOCRDerived: false
        )

        try await metadataStore.saveChunkMetadata([meta], for: bookKey)
        let vec = try await mockEmbedding.embedPassage(meta.snippet)
        try await indexStore.add(chunkID: meta.chunkID, vector: vec, bookFingerprintKey: bookKey)

        let hits = try await service.searchLibrary(query: "נרות שבת", maxHits: 3)
        #expect(!hits.isEmpty)
        #expect(hits[0].chunkID == "hebrew_chunk_1")
        #expect(hits[0].snippet.contains("הדלקת נרות"))
    }
}
