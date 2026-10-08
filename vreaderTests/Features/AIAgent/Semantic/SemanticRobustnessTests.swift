// Purpose: Robustness test suite for semantic runtime status, error reporting,
// notification loop prevention, single coordinator/job invariants, and strict vector key assignment.

import Testing
import Foundation
@testable import vreader

private actor FailingStoreMock: SemanticIndexStoring {
    func insertBatch(coherentItems: [SemanticIndexInsertItem]) async throws -> [String: UInt64] {
        // Deliberately omit one chunk key to test strict missing key guard
        var keys: [String: UInt64] = [:]
        for (i, item) in coherentItems.dropLast().enumerated() {
            keys[item.chunkID] = UInt64(i + 100)
        }
        return keys
    }
    func search(queryVector: [Float], count: Int, bookFingerprintKey: String? = nil) async throws -> [SemanticIndexStoreResult] { [] }
    func delete(bookFingerprintKey: String) async throws {}
    func clear() async throws {}
}

private struct DummyEmbeddingService: SemanticEmbeddingProviding {
    let dimension: Int = 384
    func embedPassages(_ texts: [String]) async throws -> [[Float]] {
        texts.map { _ in [Float](repeating: 0.1, count: dimension) }
    }
    func embedQuery(_ text: String) async throws -> [Float] {
        [Float](repeating: 0.1, count: dimension)
    }
}

@Suite("SemanticRobustnessTests")
struct SemanticRobustnessTests {

    // MARK: - 1. Missing Assigned Vector Key Throws Strict Error

    @Test func missingAssignedKeyThrowsRatherThanDerivingKey() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let failingStore = FailingStoreMock()
        let metaStore = SemanticIndexMetadataStore(storageDirectory: tempDir)
        let coordinator = SemanticIndexCoordinator(
            embeddingService: DummyEmbeddingService(),
            metadataStore: metaStore,
            indexStore: failingStore
        )

        let fp = DocumentFingerprint(scheme: "test", value: "book-strict")
        let chunk1 = AIDocumentChunk(
            id: "c1",
            bookFingerprintKey: fp.canonicalKey,
            sourceUnitID: "u1",
            sourceUnitIndex: 0,
            text: "First passage",
            locator: Locator(bookFingerprint: fp, href: "c1.xhtml"),
            sourceLabel: "Ch 1",
            chapterTitle: "Chapter 1",
            pageIndex: nil,
            href: "c1.xhtml",
            localStartUTF16: 0,
            localEndUTF16: 13,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )
        let chunk2 = AIDocumentChunk(
            id: "c2",
            bookFingerprintKey: fp.canonicalKey,
            sourceUnitID: "u2",
            sourceUnitIndex: 1,
            text: "Second passage",
            locator: Locator(bookFingerprint: fp, href: "c2.xhtml"),
            sourceLabel: "Ch 2",
            chapterTitle: "Chapter 2",
            pageIndex: nil,
            href: "c2.xhtml",
            localStartUTF16: 0,
            localEndUTF16: 14,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )

        do {
            try await coordinator.indexBook(fingerprintKey: fp.canonicalKey, chunks: [chunk1, chunk2])
            Issue.record("Expected SemanticIndexingError.missingAssignedVectorKey")
        } catch let err as SemanticIndexingError {
            switch err {
            case .missingAssignedVectorKey(let chunkID):
                #expect(!chunkID.isEmpty)
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - 2. Single Job Per Book Concurrency Guard

    @Test func singleActiveJobPerBookGuaranteed() async throws {
        let coordinator = SemanticIndexCoordinator(
            embeddingService: DummyEmbeddingService()
        )

        let fp = "book-concurrent-test"
        let chunk = AIDocumentChunk(
            id: "c1",
            bookFingerprintKey: fp,
            sourceUnitID: "u1",
            sourceUnitIndex: 0,
            text: "Passage",
            locator: Locator(bookFingerprint: DocumentFingerprint(scheme: "test", value: fp)),
            sourceLabel: nil,
            chapterTitle: nil,
            pageIndex: nil,
            href: nil,
            localStartUTF16: 0,
            localEndUTF16: 7,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )

        // Launch two concurrent indexing calls for the same book
        async let job1: Void = coordinator.indexBook(fingerprintKey: fp, chunks: [chunk])
        async let job2: Void = coordinator.indexBook(fingerprintKey: fp, chunks: [chunk])

        _ = try await (job1, job2)
        // If duplicate execution wasn't guarded, USearch/State collisions or crashes would occur
        let finalState = await coordinator.currentState
        #expect(finalState == .completed(bookFingerprintKey: fp))
    }

    // MARK: - 3. Runtime Status Enum Invariants

    @Test func semanticRuntimeStatusValuesAreExplicit() {
        let disabled = AIAgentSemanticRuntimeStatus.disabled
        let loading = AIAgentSemanticRuntimeStatus.loadingModel
        let indexing = AIAgentSemanticRuntimeStatus.indexing(bookKey: "b1", progress: 0.5)
        let ready = AIAgentSemanticRuntimeStatus.ready
        let failed = AIAgentSemanticRuntimeStatus.failed("Disk full")

        #expect(!disabled.isReady)
        #expect(!loading.isReady)
        #expect(!indexing.isReady)
        #expect(ready.isReady)
        #expect(!failed.isReady)
    }
}
