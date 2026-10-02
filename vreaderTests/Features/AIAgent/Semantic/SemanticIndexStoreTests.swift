// Purpose: Unit tests for SemanticIndexStore vector indexing and ANN similarity search.
// Validates vector insertion, dimension guard, nearest-neighbor query, and book deletion.

import Testing
import Foundation
@testable import vreader

@Suite("SemanticIndexStoreTests")
struct SemanticIndexStoreTests {

    private func makeIsolatedStore(dimension: Int) -> SemanticIndexStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SemanticIndexStoreTests-\(UUID().uuidString)")
        return SemanticIndexStore(dimension: dimension, indexDirectory: dir)
    }

    @Test func dimensionValidationRejectsMismatchedVectors() async throws {
        let store = makeIsolatedStore(dimension: 4)

        // Valid dimension
        try await store.add(chunkID: "c1", vector: [1.0, 0.0, 0.0, 0.0], bookFingerprintKey: "book-1")

        // Invalid dimension (3 instead of 4)
        do {
            try await store.add(chunkID: "c2", vector: [1.0, 0.0, 0.0], bookFingerprintKey: "book-1")
            Issue.record("Expected dimension mismatch error")
        } catch {
            // Expected error
        }
    }

    @Test func topKQueryReturnsNearestNeighbors() async throws {
        let store = makeIsolatedStore(dimension: 3)

        // Unit vectors along axes
        try await store.add(chunkID: "x_axis", vector: [1.0, 0.0, 0.0], bookFingerprintKey: "b1")
        try await store.add(chunkID: "y_axis", vector: [0.0, 1.0, 0.0], bookFingerprintKey: "b1")
        try await store.add(chunkID: "z_axis", vector: [0.0, 0.0, 1.0], bookFingerprintKey: "b1")

        // Query vector close to x_axis
        let results = try await store.search(queryVector: [0.99, 0.05, 0.0], count: 2)

        #expect(!results.isEmpty)
        #expect(results[0].chunkID == "x_axis")
        #expect(results[0].similarity > 0.9)
    }

    @Test func deleteBookRemovesAssociatedVectors() async throws {
        let store = makeIsolatedStore(dimension: 2)

        try await store.add(chunkID: "c1", vector: [1.0, 0.0], bookFingerprintKey: "b1")
        try await store.add(chunkID: "c2", vector: [0.0, 1.0], bookFingerprintKey: "b2")

        var b1Results = try await store.search(queryVector: [1.0, 0.0], count: 5, bookFingerprintKey: "b1")
        #expect(b1Results.count == 1)

        try await store.delete(bookFingerprintKey: "b1")

        b1Results = try await store.search(queryVector: [1.0, 0.0], count: 5, bookFingerprintKey: "b1")
        #expect(b1Results.isEmpty)

        // b2 remains intact
        let b2Results = try await store.search(queryVector: [0.0, 1.0], count: 5, bookFingerprintKey: "b2")
        #expect(b2Results.count == 1)
        #expect(b2Results[0].chunkID == "c2")
    }

    @Test func countReflectsActiveVectors() async throws {
        let store = makeIsolatedStore(dimension: 2)
        #expect(await store.count() == 0)

        try await store.add(chunkID: "c1", vector: [1.0, 0.0], bookFingerprintKey: "b1")
        try await store.add(chunkID: "c2", vector: [0.0, 1.0], bookFingerprintKey: "b1")
        #expect(await store.count() == 2)

        await store.clear()
        #expect(await store.count() == 0)
    }
}
