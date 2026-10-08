// Purpose: Integration test suite for AIAgentSemanticLibraryIndexer.
// Verifies format extraction, deterministic embedding, persistent storage,
// library semantic search, deletion cleanup, cancellation, and duplicate job prevention.

import Testing
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

private final class MockLibraryStore: LibraryPersisting, @unchecked Sendable {
    var books: [LibraryBookItem] = []

    func fetchAllLibraryBooks() async throws -> [LibraryBookItem] {
        books
    }
    func fetchBook(withKey key: String) async throws -> LibraryBookItem? {
        books.first { $0.fingerprintKey == key }
    }
    func deleteBook(fingerprintKey: String) async throws {
        books.removeAll { $0.fingerprintKey == fingerprintKey }
    }
    func updateLastOpened(forBookWithKey key: String, at date: Date) async throws {}
    func toggleFavorite(forBookWithKey key: String) async throws -> Bool { false }
    func addBook(_ book: LibraryBookItem) async throws {}
    func updateBook(_ book: LibraryBookItem) async throws {}
}

private struct DeterministicTestEmbedder: SemanticEmbeddingProviding {
    let dimension: Int = 384

    func embedPassages(_ texts: [String]) async throws -> [[Float]] {
        texts.map { text in
            var v = [Float](repeating: 0.0, count: dimension)
            let hash = abs(text.hashValue) % dimension
            v[hash] = 1.0
            return v
        }
    }

    func embedQuery(_ text: String) async throws -> [Float] {
        try await embedPassages([text]).first ?? [Float](repeating: 0.0, count: dimension)
    }
}

@Suite("AIAgentSemanticLibraryIndexerTests")
struct AIAgentSemanticLibraryIndexerTests {

    @Test func libraryIndexerIndexesTxtAndPdfAndSearchesPersistedHits() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let indexDir = tempDir.appendingPathComponent("vectors")
        let metaDir = tempDir.appendingPathComponent("metadata")

        let indexStore = SemanticIndexStore(dimension: 384, indexDirectory: indexDir)
        let metadataStore = SemanticIndexMetadataStore(storageDirectory: metaDir)
        let embedder = DeterministicTestEmbedder()
        let coordinator = SemanticIndexCoordinator(
            embeddingService: embedder,
            metadataStore: metadataStore,
            indexStore: indexStore
        )

        // 1. Prepare TXT fixture
        let txtKey = "lib:txt:\(UUID().uuidString)"
        let txtURL = ImportedBookFileURL.resolve(fingerprintKey: txtKey, format: "txt")
        try? FileManager.default.createDirectory(at: txtURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let txtContent = "The quick brown fox jumps over the lazy dog. Chapter on astronomy and stellar mechanics."
        try txtContent.write(to: txtURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: txtURL) }

        // 2. Prepare PDF fixture
        let pdfKey = "lib:pdf:\(UUID().uuidString)"
        let pdfURL = ImportedBookFileURL.resolve(fingerprintKey: pdfKey, format: "pdf")
        #if canImport(UIKit)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400))
        let pdfData = renderer.pdfData { ctx in
            ctx.beginPage()
            let str = "Quantum thermodynamics and statistical physics notes." as NSString
            str.draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
        }
        try pdfData.write(to: pdfURL)
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        #endif

        let mockLib = MockLibraryStore()
        mockLib.books = [
            LibraryBookItem(
                fingerprintKey: txtKey,
                title: "Astronomy Book",
                author: "Astronomer",
                coverImagePath: nil,
                format: "txt",
                fileByteCount: Int64(txtContent.utf8.count),
                addedAt: Date(),
                lastOpenedAt: nil,
                isFavorite: false,
                totalReadingSeconds: 0,
                fileState: .present,
                blobPath: nil,
                collectionNames: []
            ),
            LibraryBookItem(
                fingerprintKey: pdfKey,
                title: "Quantum Physics Book",
                author: "Physicist",
                coverImagePath: nil,
                format: "pdf",
                fileByteCount: 1024,
                addedAt: Date(),
                lastOpenedAt: nil,
                isFavorite: false,
                totalReadingSeconds: 0,
                fileState: .present,
                blobPath: nil,
                collectionNames: []
            )
        ]

        let indexer = AIAgentSemanticLibraryIndexer(
            library: mockLib,
            coordinator: coordinator,
            metadataStore: metadataStore,
            indexStore: indexStore,
            embeddingService: embedder,
            ocrService: nil
        )

        // Run library indexing
        await indexer.startIndexing(forceRebuild: true)

        // Wait for completion
        for _ in 0..<50 {
            let state = await indexer.state
            if case .completed = state { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let finalState = await indexer.state
        #expect(finalState.isIndexing == false)

        // Verify metadata was persisted
        let txtMeta = await metadataStore.fetchMetadata(forBook: txtKey)
        #expect(txtMeta != nil)
        #expect(txtMeta?.chunkCount ?? 0 > 0)

        // Verify search finds indexed book
        let searchService = SemanticSearchService(
            embeddingService: embedder,
            metadataStore: metadataStore,
            indexStore: indexStore
        )
        let hits = try await searchService.searchLibrary(query: "astronomy", maxHits: 5)
        #expect(!hits.isEmpty)
        #expect(hits.contains { $0.bookFingerprintKey == txtKey })

        // 3. Test Deletion Cleanup
        try await indexer.deleteIndex(forBookKey: txtKey)
        let deletedMeta = await metadataStore.fetchMetadata(forBook: txtKey)
        #expect(deletedMeta == nil)

        // Remaining book is still present
        #if canImport(UIKit)
        let pdfMeta = await metadataStore.fetchMetadata(forBook: pdfKey)
        #expect(pdfMeta != nil)
        #endif
    }

    // MARK: - Duplicate Job Prevention

    @Test func startIndexingIgnoresDuplicateConcurrentInvocations() async {
        let mockLib = MockLibraryStore()
        let coordinator = SemanticIndexCoordinator()
        let indexer = AIAgentSemanticLibraryIndexer(
            library: mockLib,
            coordinator: coordinator
        )

        await indexer.startIndexing()
        let state1 = await indexer.state
        // Re-invoking while active shouldn't crash or create new task
        await indexer.startIndexing()
        let state2 = await indexer.state
        #expect(state1 == state2)
        await indexer.cancelIndexing()
    }
}
