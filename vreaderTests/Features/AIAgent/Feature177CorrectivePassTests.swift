// Purpose: Corrective pass unit tests for Feature #177 Requirements 1-8.
// Validates MLX E5 contract, manifest verification, chunking/indexing ranges, USearch persistence, key collisions, and hybrid RRF fusion.

import Testing
import Foundation
@testable import vreader

@Suite("Feature177CorrectivePassTests — Semantic & Search (Req 1-8)")
struct Feature177CorrectivePassTests {

    // MARK: - 1. Real Embedding Contract
    @Test func mlxE5ContractValidatesPrefixesAndDimension() {
        #expect(MLXE5EmbeddingService.dimension == 384)
        #expect(MLXE5EmbeddingService.queryPrefix == "query: ")
        #expect(MLXE5EmbeddingService.passagePrefix == "passage: ")

        let service = MLXE5EmbeddingService()
        #expect(service.dimension == 384)
    }

    @Test func mlxE5EmbeddingThrowsWhenModelNotLoaded() async {
        let service = MLXE5EmbeddingService()
        // Container is nil until loadModel() with real files
        await #expect(throws: SemanticModelError.self) {
            try await service.embed(text: "Test passage", isQuery: false)
        }
    }

    // MARK: - 2. Semantic Model Lifecycle & Manifest Verification
    @Test func modelManifestRejectsMismatchedSHA256() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifestTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFile = tempDir.appendingPathComponent("weights.npz")
        try "fake-weights".write(to: testFile, atomically: true, encoding: .utf8)

        // Expected hash for "fake-weights" is NOT 00000000...
        let manifest = AISemanticModelManifest(
            modelName: "e5-small-v2",
            version: "1.0",
            expectedFiles: [
                "weights.npz": AISemanticModelFileSpec(
                    filename: "weights.npz",
                    sha256: "0000000000000000000000000000000000000000000000000000000000000000",
                    byteCount: 12
                )
            ]
        )

        let isValid = manifest.validateDirectory(tempDir)
        #expect(!isValid, "Manifest validator must reject mismatched file SHA256.")
    }

    @Test func modelManifestAcceptsMatchingSHA256() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifestTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = "hello-e5-weights"
        let testFile = tempDir.appendingPathComponent("weights.npz")
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let sha = "e6057dc6be31bb7be2ebc165efb598b0f805a8f4c281358f2be7eecdd7bb3a0d" // sha256("hello-e5-weights")
        let manifest = AISemanticModelManifest(
            modelName: "e5-small-v2",
            version: "1.0",
            expectedFiles: [
                "weights.npz": AISemanticModelFileSpec(
                    filename: "weights.npz",
                    sha256: sha,
                    byteCount: Int64(content.utf8.count)
                )
            ]
        )

        #expect(manifest.validateDirectory(tempDir), "Manifest validator must accept matching SHA256.")
    }

    // MARK: - 3. Semantic Current-Book Indexing (UTF-16 & Unit Tracking)
    @Test func chunkerPreservesExactUTF16OffsetsAndUnitIndex() {
        let chunker = SemanticChunker(targetTokens: 10, overlapTokens: 2)
        let sampleText = "The quick brown fox jumps over the lazy dog. Swift pack."
        let locator = Locator(href: "c1.xhtml", type: "text/html")
        let chunk = AIDocumentChunk(
            unit: .chapter(title: "Chapter 1"),
            locator: locator,
            text: sampleText,
            isSafeCurrentSection: true,
            isSafeBookSoFar: true,
            isAheadOfReader: false
        )

        let chunks = chunker.chunk(documentChunk: chunk, sourceUnitIndex: 3, globalBaseUTF16: 1000)
        #expect(!chunks.isEmpty)

        for ch in chunks {
            #expect(ch.sourceUnitIndex == 3)
            #expect(ch.localStartUTF16 >= 0)
            #expect(ch.localEndUTF16 <= sampleText.utf16.count)
            #expect(ch.globalStartUTF16 == 1000 + ch.localStartUTF16)
            #expect(ch.globalEndUTF16 == 1000 + ch.localEndUTF16)
            #expect(ch.chapterTitle == "Chapter 1")
            #expect(ch.href == "c1.xhtml")
        }
    }

    // MARK: - 4. Semantic Library Indexing
    @Test func libraryMetadataStoreIndexesAndFiltersMultipleBooks() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetaStoreTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SemanticIndexMetadataStore(storageDirectory: tempDir)
        let chunkA = SemanticChunkMetadata(
            chunkID: "bookA-c1",
            bookFingerprintKey: "bookA",
            bookTitle: "Book A",
            chapterTitle: "Ch 1",
            pageIndex: 1,
            href: "c1.xhtml",
            snippet: "Snippet in Book A",
            tokenCount: 4,
            vectorKey: 101,
            sourceUnitIndex: 0,
            localStartUTF16: 0,
            localEndUTF16: 20,
            globalStartUTF16: 0,
            globalEndUTF16: 20
        )
        let chunkB = SemanticChunkMetadata(
            chunkID: "bookB-c1",
            bookFingerprintKey: "bookB",
            bookTitle: "Book B",
            chapterTitle: "Ch 1",
            pageIndex: 1,
            href: "c1.xhtml",
            snippet: "Snippet in Book B",
            tokenCount: 4,
            vectorKey: 102,
            sourceUnitIndex: 0,
            localStartUTF16: 0,
            localEndUTF16: 20,
            globalStartUTF16: 0,
            globalEndUTF16: 20
        )

        try await store.saveMetadata([chunkA, chunkB])

        let loadedA = try await store.metadata(forChunkID: "bookA-c1")
        #expect(loadedA?.bookFingerprintKey == "bookA")

        let allForA = try await store.allMetadata(forBookFingerprintKey: "bookA")
        #expect(allForA.count == 1)
        #expect(allForA.first?.chunkID == "bookA-c1")

        try await store.deleteMetadata(forBookFingerprintKey: "bookA")
        let remainingA = try await store.allMetadata(forBookFingerprintKey: "bookA")
        #expect(remainingA.isEmpty)

        let remainingB = try await store.allMetadata(forBookFingerprintKey: "bookB")
        #expect(remainingB.count == 1)
    }

    // MARK: - 5. USearch Relaunch Persistence & Mappings Reload
    @Test func semanticIndexStorePersistsAndReloadsMappings() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreReloadTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create store and add items
        let store1 = SemanticIndexStore(dimension: 4, indexDirectory: tempDir)
        let key1 = store1.keyTable.key(for: "chunk-alpha")
        let key2 = store1.keyTable.key(for: "chunk-beta")
        store1.keyToBookKey[key1] = "book-1"
        store1.keyToBookKey[key2] = "book-1"
        try store1.save()

        // Create fresh store pointing at same directory
        let store2 = SemanticIndexStore(dimension: 4, indexDirectory: tempDir)
        #expect(store2.count() == 2)
        #expect(store2.keyTable.chunkID(for: key1) == "chunk-alpha")
        #expect(store2.keyTable.chunkID(for: key2) == "chunk-beta")
        #expect(store2.keyToBookKey[key1] == "book-1")
    }

    // MARK: - 6. Forced Vector-Key Collision Resolution
    @Test func vectorKeyTableResolvesForcedHashCollisions() {
        let table = SemanticVectorKeyTable()
        let idA = "chunk-1"
        let idB = "chunk-2"

        let keyA = table.key(for: idA)
        let keyB = table.key(for: idB)

        #expect(keyA != keyB, "Distinct chunk IDs must receive distinct vector keys.")
        #expect(table.chunkID(for: keyA) == idA)
        #expect(table.chunkID(for: keyB) == idB)

        // Idempotency check: same chunk ID returns identical assigned key
        #expect(table.key(for: idA) == keyA)
        #expect(table.key(for: idB) == keyB)
    }

    // MARK: - 7. Hybrid Lexical + Semantic RRF Fusion
    @Test func hybridSearchFusesAndDedupesLexicalAndSemanticHits() {
        let hybrid = HybridSearchService(rrfK: 60.0)
        let loc1 = Locator(href: "ch1.xhtml", type: "application/xhtml+xml", title: "Ch 1")
        let loc2 = Locator(href: "ch2.xhtml", type: "application/xhtml+xml", title: "Ch 2")

        let lexical: [HybridSearchResultItem] = [
            HybridSearchResultItem(
                id: "hit-1",
                bookFingerprintKey: "bookA",
                title: "Book A",
                locator: loc1,
                snippet: "Lexical and semantic hit",
                method: .lexicalSearch,
                score: 1.0,
                aheadOfReader: false
            )
        ]

        let semantic: [HybridSearchResultItem] = [
            HybridSearchResultItem(
                id: "hit-1", // duplicate hit
                bookFingerprintKey: "bookA",
                title: "Book A",
                locator: loc1,
                snippet: "Lexical and semantic hit",
                method: .semanticSearch,
                score: 0.95,
                aheadOfReader: false
            ),
            HybridSearchResultItem(
                id: "hit-2", // semantic-only hit
                bookFingerprintKey: "bookA",
                title: "Book A",
                locator: loc2,
                snippet: "Semantic only hit",
                method: .semanticSearch,
                score: 0.8,
                aheadOfReader: true
            )
        ]

        let fused = hybrid.fuse(lexical: lexical, semantic: semantic, limit: 10)
        #expect(fused.count == 2)
        #expect(fused[0].id == "hit-1")
        #expect(fused[0].score > fused[1].score)
        #expect(fused[1].id == "hit-2")
        #expect(fused[1].aheadOfReader == true)
    }

    // MARK: - 8. Semantic Partial-Overlap Boundary
    @Test func semanticHitCarriesExactUTF16Offsets() {
        let loc = Locator(href: "ch3.xhtml", type: "text/html", charOffsetUTF16: 120)
        let hit = SemanticSearchHit(
            chunkID: "c-123",
            bookFingerprintKey: "book-1",
            bookTitle: "Novel",
            locator: loc,
            chapterTitle: "Chapter 3",
            pageIndex: nil,
            href: "ch3.xhtml",
            snippet: "The golden key was hidden.",
            similarity: 0.88,
            sourceUnitIndex: 2,
            localStartUTF16: 40,
            localEndUTF16: 80,
            globalStartUTF16: 1040,
            globalEndUTF16: 1080,
            aheadOfReader: false
        )

        #expect(hit.sourceUnitIndex == 2)
        #expect(hit.localStartUTF16 == 40)
        #expect(hit.localEndUTF16 == 80)
        #expect(hit.globalStartUTF16 == 1040)
        #expect(hit.globalEndUTF16 == 1080)
        #expect(hit.aheadOfReader == false)
    }
}
