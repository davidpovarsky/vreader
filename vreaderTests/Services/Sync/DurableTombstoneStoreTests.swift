// Purpose: Tests for DurableTombstoneStore — JSON-file-backed tombstone persistence.
// Covers: add/query/purge, restart survival, empty/corrupt file recovery,
// concurrent access via actor isolation, idempotent adds, Unicode entity IDs.

import Testing
import Foundation
@testable import vreader

@Suite("DurableTombstoneStore")
struct DurableTombstoneStoreTests {

    // MARK: - Helpers

    /// Creates a unique temp directory for each test.
    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DurableTombstoneStoreTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// The JSON file path that the store uses within a given directory.
    private func jsonFile(in dir: URL) -> URL {
        dir.appendingPathComponent("tombstones.json")
    }

    // MARK: - Add and Query

    @Test func addTombstoneAndQueryReturnsTrue() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)
        let now = SyncTestHelpers.refDate

        try await store.addTombstone(
            entityType: .bookmark,
            entityId: "bm-001",
            deviceId: SyncTestHelpers.deviceA,
            deletedAt: now
        )

        let result = await store.hasTombstone(entityType: .bookmark, entityId: "bm-001")
        #expect(result.exists == true)
        #expect(result.deletedAt == now)
    }

    @Test func queryNonexistentTombstoneReturnsFalse() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)

        let result = await store.hasTombstone(entityType: .bookmark, entityId: "nonexistent")
        #expect(result.exists == false)
        #expect(result.deletedAt == nil)
    }

    // MARK: - allTombstones

    @Test func allTombstonesReturnsStoredEntries() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)
        let now = SyncTestHelpers.refDate

        try await store.addTombstone(entityType: .bookmark, entityId: "b1", deviceId: "d", deletedAt: now)
        try await store.addTombstone(entityType: .highlight, entityId: "h1", deviceId: "d", deletedAt: now)

        let all = await store.allTombstones
        #expect(all.count == 2)
    }

    @Test func emptyStoreAllTombstonesIsEmpty() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)

        let all = await store.allTombstones
        #expect(all.isEmpty)
    }

    // MARK: - count

    @Test func countReturnsTotalTombstones() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)
        let now = SyncTestHelpers.refDate

        try await store.addTombstone(entityType: .bookmark, entityId: "b1", deviceId: "d", deletedAt: now)
        try await store.addTombstone(entityType: .highlight, entityId: "h1", deviceId: "d", deletedAt: now)

        let c = await store.count
        #expect(c == 2)
    }

    @Test func emptyStoreCountIsZero() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)

        let c = await store.count
        #expect(c == 0)
    }

    // MARK: - Persistence to file

    @Test func addTombstonePersistsToJSONFile() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)
        let now = SyncTestHelpers.refDate

        try await store.addTombstone(entityType: .bookmark, entityId: "bm-001", deviceId: "d", deletedAt: now)

        // Verify the file exists
        let file = jsonFile(in: dir)
        #expect(FileManager.default.fileExists(atPath: file.path))

        // Verify file content is valid JSON
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([CodableTombstone].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].entityId == "bm-001")
    }

    // MARK: - Restart survival

    @Test func survivesRestartWithSameDirectory() async throws {
        let dir = try makeTempDir()
        let now = SyncTestHelpers.refDate

        // First instance: add tombstones
        let store1 = DurableTombstoneStore(directory: dir)
        try await store1.addTombstone(entityType: .bookmark, entityId: "bm-1", deviceId: "d", deletedAt: now)
        try await store1.addTombstone(entityType: .highlight, entityId: "hl-1", deviceId: "d", deletedAt: now)

        // Second instance: same directory — should see data
        let store2 = DurableTombstoneStore(directory: dir)
        let result1 = await store2.hasTombstone(entityType: .bookmark, entityId: "bm-1")
        let result2 = await store2.hasTombstone(entityType: .highlight, entityId: "hl-1")

        #expect(result1.exists == true)
        #expect(result1.deletedAt == now)
        #expect(result2.exists == true)
    }

    // MARK: - Empty file recovery

    @Test func emptyFileProducesEmptyStore() async throws {
        let dir = try makeTempDir()
        let file = jsonFile(in: dir)

        // Write an empty file
        try Data().write(to: file)

        let store = DurableTombstoneStore(directory: dir)
        let c = await store.count
        #expect(c == 0)
    }

    // MARK: - Corrupt file recovery

    @Test func corruptFileProducesEmptyStore() async throws {
        let dir = try makeTempDir()
        let file = jsonFile(in: dir)

        // Write corrupt JSON
        try Data("not valid json {{{".utf8).write(to: file)

        let store = DurableTombstoneStore(directory: dir)
        let c = await store.count
        #expect(c == 0)

        // Store should still be functional — add works after corrupt load
        try await store.addTombstone(entityType: .bookmark, entityId: "b1", deviceId: "d", deletedAt: SyncTestHelpers.refDate)
        let c2 = await store.count
        #expect(c2 == 1)
    }

    // MARK: - Purge

    @Test func purgeTombstonesRemovesOldEntries() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)
        let thirtyOneDaysAgo = SyncTestHelpers.refDate.addingTimeInterval(-31 * 24 * 3600)
        let fiveDaysAgo = SyncTestHelpers.refDate.addingTimeInterval(-5 * 24 * 3600)

        try await store.addTombstone(entityType: .bookmark, entityId: "old", deviceId: "d", deletedAt: thirtyOneDaysAgo)
        try await store.addTombstone(entityType: .bookmark, entityId: "recent", deviceId: "d", deletedAt: fiveDaysAgo)

        let purged = await store.purgeTombstones(olderThan: SyncTestHelpers.refDate.addingTimeInterval(-30 * 24 * 3600))
        #expect(purged == 1)
        #expect(await store.hasTombstone(entityType: .bookmark, entityId: "old").exists == false)
        #expect(await store.hasTombstone(entityType: .bookmark, entityId: "recent").exists == true)
    }

    @Test func purgeRewritesJSONFile() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)
        let old = SyncTestHelpers.refDate.addingTimeInterval(-40 * 24 * 3600)

        try await store.addTombstone(entityType: .bookmark, entityId: "old1", deviceId: "d", deletedAt: old)
        try await store.addTombstone(entityType: .highlight, entityId: "old2", deviceId: "d", deletedAt: old)

        _ = await store.purgeTombstones(olderThan: SyncTestHelpers.refDate)

        // File should now contain an empty array
        let file = jsonFile(in: dir)
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([CodableTombstone].self, from: data)
        #expect(decoded.isEmpty)
    }

    @Test func purgeOnEmptyStoreReturnsZero() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)

        let purged = await store.purgeTombstones(olderThan: SyncTestHelpers.refDate)
        #expect(purged == 0)
    }

    // MARK: - Idempotent adds

    @Test func idempotentAddKeepsLatestDate() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)
        let earlier = SyncTestHelpers.date(offsetBy: -100)
        let later = SyncTestHelpers.date(offsetBy: 100)

        try await store.addTombstone(entityType: .bookmark, entityId: "bm-1", deviceId: "d", deletedAt: earlier)
        try await store.addTombstone(entityType: .bookmark, entityId: "bm-1", deviceId: "d", deletedAt: later)

        let result = await store.hasTombstone(entityType: .bookmark, entityId: "bm-1")
        #expect(result.deletedAt == later)

        let c = await store.count
        #expect(c == 1)
    }

    @Test func idempotentAddDoesNotOverwriteWithOlderDate() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)
        let earlier = SyncTestHelpers.date(offsetBy: -100)
        let later = SyncTestHelpers.date(offsetBy: 100)

        try await store.addTombstone(entityType: .bookmark, entityId: "bm-1", deviceId: "d", deletedAt: later)
        try await store.addTombstone(entityType: .bookmark, entityId: "bm-1", deviceId: "d", deletedAt: earlier)

        let result = await store.hasTombstone(entityType: .bookmark, entityId: "bm-1")
        #expect(result.deletedAt == later)
    }

    // MARK: - Different entity types

    @Test func differentEntityTypesAreIndependent() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)
        let now = SyncTestHelpers.refDate

        try await store.addTombstone(entityType: .bookmark, entityId: "id-1", deviceId: "d", deletedAt: now)
        try await store.addTombstone(entityType: .highlight, entityId: "id-1", deviceId: "d", deletedAt: now)

        #expect(await store.hasTombstone(entityType: .bookmark, entityId: "id-1").exists == true)
        #expect(await store.hasTombstone(entityType: .highlight, entityId: "id-1").exists == true)
        #expect(await store.hasTombstone(entityType: .annotation, entityId: "id-1").exists == false)
    }

    // MARK: - Unicode entity IDs

    @Test func unicodeEntityIdsWork() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)
        let now = SyncTestHelpers.refDate

        try await store.addTombstone(entityType: .annotation, entityId: "note-\u{4F60}\u{597D}", deviceId: "d", deletedAt: now)

        let result = await store.hasTombstone(entityType: .annotation, entityId: "note-\u{4F60}\u{597D}")
        #expect(result.exists == true)

        // Verify it survives a restart with Unicode
        let store2 = DurableTombstoneStore(directory: dir)
        let result2 = await store2.hasTombstone(entityType: .annotation, entityId: "note-\u{4F60}\u{597D}")
        #expect(result2.exists == true)
    }

    // MARK: - Concurrent adds (actor serialization)

    @Test func concurrentAddsDoNotLoseData() async throws {
        let dir = try makeTempDir()
        let store = DurableTombstoneStore(directory: dir)
        let now = SyncTestHelpers.refDate

        // Fire off 50 concurrent adds
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    try await store.addTombstone(
                        entityType: .bookmark,
                        entityId: "concurrent-\(i)",
                        deviceId: "d",
                        deletedAt: now.addingTimeInterval(Double(i))
                    )
                }
            }
        }

        let c = await store.count
        #expect(c == 50)
    }

    // MARK: - No file yet (directory exists but no tombstones.json)

    @Test func noFileYetProducesEmptyStore() async throws {
        let dir = try makeTempDir()
        // Directory exists but no tombstones.json
        let store = DurableTombstoneStore(directory: dir)
        let c = await store.count
        #expect(c == 0)
    }
}
