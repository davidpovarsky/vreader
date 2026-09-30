// Purpose: Unit tests for SemanticIndexMetadata and SemanticIndexMetadataStore.
// Tests metadata persistence, version compatibility validation, and rebuild triggers.

import Testing
import Foundation
@testable import vreader

@Suite("SemanticIndexMetadataTests")
struct SemanticIndexMetadataTests {

    @Test func metadataStoreSavesAndRetrievesChunks() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SemanticIndexMetadataStore(storageDirectory: tempDir)
        let locator = Locator(href: "ch1.xhtml", type: "application/xhtml+xml", title: "Chapter 1")

        let chunkMeta = SemanticChunkMetadata(
            chunkID: "chunk_1",
            bookFingerprintKey: "book-1",
            bookTitle: "Test Book",
            locator: locator,
            sourceLabel: "Ch. 1",
            chapterTitle: "Chapter 1",
            pageIndex: nil,
            href: "ch1.xhtml",
            snippet: "A short snippet of text",
            charRange: 0..<50,
            isOCRDerived: false
        )

        try await store.saveChunkMetadata([chunkMeta], for: "book-1")

        let fetched = try await store.metadata(for: "chunk_1")
        #expect(fetched != nil)
        #expect(fetched?.bookTitle == "Test Book")
        #expect(fetched?.snippet == "A short snippet of text")
        #expect(fetched?.locator.href == "ch1.xhtml")

        let allChunks = try await store.allChunks(for: "book-1")
        #expect(allChunks.count == 1)
        #expect(allChunks[0].chunkID == "chunk_1")
    }

    @Test func metadataStoreDeleteRemovesAllBookEntries() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SemanticIndexMetadataStore(storageDirectory: tempDir)
        let locator = Locator(href: "page_1.pdf", type: "application/pdf")
        let chunkMeta = SemanticChunkMetadata(
            chunkID: "chunk_pdf",
            bookFingerprintKey: "book-pdf",
            bookTitle: "PDF Doc",
            locator: locator,
            sourceLabel: "Page 1",
            chapterTitle: nil,
            pageIndex: 0,
            href: "page_1.pdf",
            snippet: "OCR text snippet",
            charRange: 0..<100,
            isOCRDerived: true
        )

        try await store.saveChunkMetadata([chunkMeta], for: "book-pdf")
        let beforeDelete = try await store.allChunks(for: "book-pdf")
        #expect(beforeDelete.count == 1)

        try await store.deleteMetadata(for: "book-pdf")
        let afterDelete = try await store.allChunks(for: "book-pdf")
        #expect(afterDelete.isEmpty)
        let fetched = try await store.metadata(for: "chunk_pdf")
        #expect(fetched == nil)
    }

    @Test func metadataCompatibilityRejectionOnVersionMismatch() {
        let meta1 = SemanticIndexMetadata(
            bookFingerprintKey: "book-1",
            embeddingDimension: 384,
            chunkerVersion: 1,
            extractionVersion: 1,
            schemaVersion: 1
        )

        let metaDifferentDimension = SemanticIndexMetadata(
            bookFingerprintKey: "book-1",
            embeddingDimension: 512,
            chunkerVersion: 1,
            extractionVersion: 1,
            schemaVersion: 1
        )

        let metaDifferentChunker = SemanticIndexMetadata(
            bookFingerprintKey: "book-1",
            embeddingDimension: 384,
            chunkerVersion: 2,
            extractionVersion: 1,
            schemaVersion: 1
        )

        #expect(meta1.isCompatible(with: meta1) == true)
        #expect(meta1.isCompatible(with: metaDifferentDimension) == false)
        #expect(meta1.isCompatible(with: metaDifferentChunker) == false)
    }
}
