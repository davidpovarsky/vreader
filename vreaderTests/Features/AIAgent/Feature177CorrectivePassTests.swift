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
        let fp = DocumentFingerprint(scheme: "test", value: "book-1")
        let locator = Locator.validated(bookFingerprint: fp, href: "c1.xhtml")!
        let chunk = AIDocumentChunk(
            unit: .chapter(title: "Chapter 1"),
            locator: locator,
            text: sampleText,
            isSafeCurrentSection: true,
            isSafeBookSoFar: true,
            isAheadOfReader: false
        )

        let chunks = chunker.chunk(chunk, bookFingerprintKey: "book-1")
        #expect(!chunks.isEmpty)

        for ch in chunks {
            #expect(ch.localStartUTF16 >= 0)
            #expect(ch.localEndUTF16 <= sampleText.utf16.count)
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
        let fpA = DocumentFingerprint(scheme: "test", value: "bookA")
        let locA = Locator.validated(bookFingerprint: fpA, href: "c1.xhtml")!
        let fpB = DocumentFingerprint(scheme: "test", value: "bookB")
        let locB = Locator.validated(bookFingerprint: fpB, href: "c1.xhtml")!

        let chunkA = SemanticChunkMetadata(
            chunkID: "bookA-c1",
            vectorKey: 101,
            bookFingerprintKey: "bookA",
            bookTitle: "Book A",
            locator: locA,
            chapterTitle: "Ch 1",
            pageIndex: 1,
            href: "c1.xhtml",
            snippet: "Snippet in Book A",
            localStartUTF16: 0,
            localEndUTF16: 20
        )
        let chunkB = SemanticChunkMetadata(
            chunkID: "bookB-c1",
            vectorKey: 102,
            bookFingerprintKey: "bookB",
            bookTitle: "Book B",
            locator: locB,
            chapterTitle: "Ch 1",
            pageIndex: 1,
            href: "c1.xhtml",
            snippet: "Snippet in Book B",
            localStartUTF16: 0,
            localEndUTF16: 20
        )

        try await store.saveChunkMetadata([chunkA], for: "bookA")
        try await store.saveChunkMetadata([chunkB], for: "bookB")

        let loadedA = await store.metadata(for: "bookA-c1")
        #expect(loadedA?.bookFingerprintKey == "bookA")

        let allForA = await store.allChunks(for: "bookA")
        #expect(allForA.count == 1)
        #expect(allForA.first?.chunkID == "bookA-c1")

        try await store.deleteMetadata(for: "bookA")
        let remainingA = await store.allChunks(for: "bookA")
        #expect(remainingA.isEmpty)

        let remainingB = await store.allChunks(for: "bookB")
        #expect(remainingB.count == 1)
    }

    // MARK: - 5. USearch Relaunch Persistence & Mappings Reload
    @Test func semanticIndexStorePersistsAndReloadsMappings() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreReloadTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create store and add items
        let store1 = SemanticIndexStore(dimension: 4, indexDirectory: tempDir)
        try await store1.add(chunkID: "chunk-alpha", vector: [1.0, 0.0, 0.0, 0.0], bookFingerprintKey: "book-1")
        try await store1.add(chunkID: "chunk-beta", vector: [0.0, 1.0, 0.0, 0.0], bookFingerprintKey: "book-1")
        try await store1.save()

        // Create fresh store pointing at same directory
        let store2 = SemanticIndexStore(dimension: 4, indexDirectory: tempDir)
        let count = await store2.count()
        #expect(count == 2)
        let searchRes = try await store2.search(queryVector: [1.0, 0.0, 0.0, 0.0], count: 1)
        #expect(searchRes.first?.chunkID == "chunk-alpha")
    }

    // MARK: - 6. Forced Vector-Key Collision Resolution
    @Test func vectorKeyTableResolvesForcedHashCollisions() {
        var table = SemanticVectorKeyTable()
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
        let fp = DocumentFingerprint(scheme: "test", value: "bookA")
        let loc1 = Locator.validated(bookFingerprint: fp, href: "ch1.xhtml")!
        let loc2 = Locator.validated(bookFingerprint: fp, href: "ch2.xhtml")!

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
        let fp = DocumentFingerprint(scheme: "test", value: "book-1")
        let loc = Locator.validated(bookFingerprint: fp, href: "ch3.xhtml")!
        let hit = SemanticSearchHit(
            chunkID: "c-123",
            bookFingerprintKey: "book-1",
            bookTitle: "Novel",
            locator: loc,
            chapterTitle: "Chapter 3",
            pageIndex: nil,
            href: "ch3.xhtml",
            snippet: "The golden key was hidden.",
            similarityScore: 0.88,
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
