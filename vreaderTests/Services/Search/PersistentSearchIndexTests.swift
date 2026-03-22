// Purpose: Tests for WI-F06 — persistent file-backed FTS5 search index.
// Verifies that SearchIndexCore can use a file path, data persists across
// init cycles, and corruption is handled gracefully.

import Testing
import Foundation
@testable import vreader

@Suite("Persistent Search Index")
struct PersistentSearchIndexTests {

    // MARK: - Helpers

    private static let testFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 1024,
        format: .txt
    )

    private static let testFP2 = DocumentFingerprint(
        contentSHA256: "bbccddee00112233bbccddee00112233bbccddee00112233bbccddee00112233",
        fileByteCount: 2048,
        format: .epub
    )

    /// Creates a unique temp directory for each test's DB file.
    private func makeTempDBPath() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("persistent-search-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("search.sqlite3")
    }

    private func makeStore(dbPath: URL) throws -> SearchIndexStore {
        let core = try SearchIndexCore(databasePath: dbPath.path)
        return try SearchIndexStore(core: core)
    }

    /// Cleanup helper.
    private func removeDB(at path: URL) {
        try? FileManager.default.removeItem(at: path)
        // SQLite may create -wal and -shm files
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path.path + "-shm"))
        try? FileManager.default.removeItem(at: path.deletingLastPathComponent())
    }

    // MARK: - File-backed DB creation

    @Test func init_withFilePath_createsDatabaseOnDisk() throws {
        let dbPath = makeTempDBPath()
        defer { removeDB(at: dbPath) }

        _ = try SearchIndexCore(databasePath: dbPath.path)

        #expect(FileManager.default.fileExists(atPath: dbPath.path),
                "Database file should exist on disk at \(dbPath.path)")
    }

    // MARK: - Persistence across init cycles

    @Test func indexBook_persistsAcrossInitCycles() throws {
        let dbPath = makeTempDBPath()
        defer { removeDB(at: dbPath) }

        // Index data in first session
        let store1 = try makeStore(dbPath: dbPath)
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Hello persistent world")]
        try store1.indexBook(fingerprintKey: Self.testFP.canonicalKey, textUnits: units)

        // Open a new session (new core + store) against the same DB file
        let store2 = try makeStore(dbPath: dbPath)
        let hits = try store2.search(
            query: "persistent",
            bookFingerprintKey: Self.testFP.canonicalKey
        )

        #expect(!hits.isEmpty, "Data indexed in session 1 should be searchable in session 2")
        #expect(hits.first?.fingerprintKey == Self.testFP.canonicalKey)
    }

    // MARK: - Metadata: isIndexed

    @Test func isIndexed_returnsTrueForPersistedBook() throws {
        let dbPath = makeTempDBPath()
        defer { removeDB(at: dbPath) }

        // Index in session 1
        let core1 = try SearchIndexCore(databasePath: dbPath.path)
        let store1 = try SearchIndexStore(core: core1)
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Persisted content")]
        try store1.indexBook(fingerprintKey: Self.testFP.canonicalKey, textUnits: units)

        // Check in session 2
        let core2 = try SearchIndexCore(databasePath: dbPath.path)
        let store2 = try SearchIndexStore(core: core2)
        let indexed = store2.isBookIndexed(fingerprintKey: Self.testFP.canonicalKey)

        #expect(indexed, "Book indexed in session 1 should be reported as indexed in session 2")
    }

    @Test func isIndexed_returnsFalseForUnindexedBook() throws {
        let dbPath = makeTempDBPath()
        defer { removeDB(at: dbPath) }

        let store = try makeStore(dbPath: dbPath)
        let indexed = store.isBookIndexed(fingerprintKey: Self.testFP.canonicalKey)

        #expect(!indexed, "Unindexed book should return false")
    }

    // MARK: - Remove book

    @Test func removeBook_deletesFromPersistentDB() throws {
        let dbPath = makeTempDBPath()
        defer { removeDB(at: dbPath) }

        // Index, then remove in session 1
        let store1 = try makeStore(dbPath: dbPath)
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "To be removed")]
        try store1.indexBook(fingerprintKey: Self.testFP.canonicalKey, textUnits: units)
        try store1.removeBook(fingerprintKey: Self.testFP.canonicalKey)

        // Check in session 2
        let store2 = try makeStore(dbPath: dbPath)
        let indexed = store2.isBookIndexed(fingerprintKey: Self.testFP.canonicalKey)
        #expect(!indexed, "Removed book should not be indexed in session 2")

        let hits = try store2.search(
            query: "removed",
            bookFingerprintKey: Self.testFP.canonicalKey
        )
        #expect(hits.isEmpty, "Removed book should have no search results")
    }

    // MARK: - Corruption recovery

    @Test func corruptDB_handledGracefully_recreatesIndex() throws {
        let dbPath = makeTempDBPath()
        defer { removeDB(at: dbPath) }

        // Create a valid DB first so the path exists
        let store1 = try makeStore(dbPath: dbPath)
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Data before corruption")]
        try store1.indexBook(fingerprintKey: Self.testFP.canonicalKey, textUnits: units)

        // Corrupt the database file by writing garbage
        try Data("THIS IS NOT A VALID SQLITE DATABASE".utf8).write(to: dbPath)

        // Opening a new core should recover gracefully (delete and recreate)
        let core2 = try SearchIndexCore(databasePath: dbPath.path)
        let store2 = try SearchIndexStore(core: core2)

        // Old data is lost (expected), but we should be able to index and search new data
        let newUnits = [TextUnit(sourceUnitId: "txt:segment:0", text: "Data after recovery")]
        try store2.indexBook(fingerprintKey: Self.testFP.canonicalKey, textUnits: newUnits)

        let hits = try store2.search(
            query: "recovery",
            bookFingerprintKey: Self.testFP.canonicalKey
        )
        #expect(!hits.isEmpty, "Should be able to search after corruption recovery")
    }

    // MARK: - Search after reopen

    @Test func searchAfterReopen_returnsResults() throws {
        let dbPath = makeTempDBPath()
        defer { removeDB(at: dbPath) }

        // Index in session 1
        let store1 = try makeStore(dbPath: dbPath)
        let units = [
            TextUnit(sourceUnitId: "txt:segment:0", text: "First chapter content"),
            TextUnit(sourceUnitId: "txt:segment:1", text: "Second chapter different words"),
        ]
        try store1.indexBook(fingerprintKey: Self.testFP.canonicalKey, textUnits: units)

        // Search in session 2
        let store2 = try makeStore(dbPath: dbPath)
        let hits = try store2.search(
            query: "chapter",
            bookFingerprintKey: Self.testFP.canonicalKey
        )

        #expect(hits.count == 2, "Both segments should be found after reopen, got \(hits.count)")
    }

    // MARK: - Content hash mismatch triggers re-index

    @Test func contentHashMismatch_triggersReindex() throws {
        let dbPath = makeTempDBPath()
        defer { removeDB(at: dbPath) }

        // Index with content hash "abc123" in session 1
        let store1 = try makeStore(dbPath: dbPath)
        let units1 = [TextUnit(sourceUnitId: "txt:segment:0", text: "Original content")]
        try store1.indexBook(fingerprintKey: Self.testFP.canonicalKey, textUnits: units1)
        store1.setContentHash(fingerprintKey: Self.testFP.canonicalKey, contentHash: "abc123")

        // Session 2: check content hash
        let store2 = try makeStore(dbPath: dbPath)
        let matchesOriginal = store2.contentHashMatches(
            fingerprintKey: Self.testFP.canonicalKey,
            contentHash: "abc123"
        )
        #expect(matchesOriginal, "Same content hash should match")

        let matchesDifferent = store2.contentHashMatches(
            fingerprintKey: Self.testFP.canonicalKey,
            contentHash: "def456"
        )
        #expect(!matchesDifferent, "Different content hash should not match")
    }

    // MARK: - Segment base offsets persist

    @Test func segmentBaseOffsets_persistAcrossSessions() throws {
        let dbPath = makeTempDBPath()
        defer { removeDB(at: dbPath) }

        // Index a book first so the metadata row exists, then store offsets
        let store1 = try makeStore(dbPath: dbPath)
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Content")]
        try store1.indexBook(fingerprintKey: Self.testFP.canonicalKey, textUnits: units)
        let offsets: [Int: Int] = [0: 0, 1: 500, 2: 1200]
        store1.setSegmentBaseOffsets(
            fingerprintKey: Self.testFP.canonicalKey,
            offsets: offsets
        )

        // Read back in session 2
        let store2 = try makeStore(dbPath: dbPath)
        let loaded = store2.getSegmentBaseOffsets(fingerprintKey: Self.testFP.canonicalKey)

        #expect(loaded == offsets, "Segment base offsets should persist across sessions")
    }

    // MARK: - In-memory init still works (backward compatibility)

    @Test func inMemoryInit_stillWorks() throws {
        // Default init (in-memory) should still work
        let core = try SearchIndexCore()
        let store = try SearchIndexStore(core: core)
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "In-memory test")]
        try store.indexBook(fingerprintKey: "test:key:100", textUnits: units)

        let hits = try store.search(query: "memory", bookFingerprintKey: "test:key:100")
        #expect(!hits.isEmpty, "In-memory store should still work")
    }

    // MARK: - Multiple books persist independently

    @Test func multipleBooksIndependent_afterReopen() throws {
        let dbPath = makeTempDBPath()
        defer { removeDB(at: dbPath) }

        // Index two books in session 1
        let store1 = try makeStore(dbPath: dbPath)
        try store1.indexBook(
            fingerprintKey: Self.testFP.canonicalKey,
            textUnits: [TextUnit(sourceUnitId: "txt:segment:0", text: "Alpha bravo")]
        )
        try store1.indexBook(
            fingerprintKey: Self.testFP2.canonicalKey,
            textUnits: [TextUnit(sourceUnitId: "epub:ch1.xhtml", text: "Charlie delta")]
        )

        // Session 2: verify isolation
        let store2 = try makeStore(dbPath: dbPath)
        let hits1 = try store2.search(
            query: "alpha",
            bookFingerprintKey: Self.testFP.canonicalKey
        )
        let hits2 = try store2.search(
            query: "alpha",
            bookFingerprintKey: Self.testFP2.canonicalKey
        )

        #expect(!hits1.isEmpty, "Book 1 should have 'alpha' results")
        #expect(hits2.isEmpty, "Book 2 should NOT have 'alpha' results")
    }
}
