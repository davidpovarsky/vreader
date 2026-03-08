// Purpose: Tests for SwiftDataSessionStore — verifies real SessionPersisting
// implementation using in-memory SwiftData.

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("SwiftDataSessionStore")
@MainActor
struct SwiftDataSessionStoreTests {

    /// Creates an in-memory ModelContainer for testing.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeFingerprint() -> DocumentFingerprint {
        DocumentFingerprint.validated(
            contentSHA256: "abc123def456abc123def456abc123def456abc123def456abc123def456abcd",
            fileByteCount: 1024,
            format: .txt
        )!
    }

    // MARK: - saveSession

    @Test("saveSession inserts new session")
    func saveSessionInserts() throws {
        let container = try makeContainer()
        let store = SwiftDataSessionStore(modelContainer: container)
        let fp = makeFingerprint()
        let session = ReadingSession(bookFingerprint: fp, startedAt: Date(), deviceId: "test")

        try store.saveSession(session)

        // Verify via a fresh context
        let context = ModelContext(container)
        let sid = session.sessionId
        let predicate = #Predicate<ReadingSession> { $0.sessionId == sid }
        var descriptor = FetchDescriptor<ReadingSession>(predicate: predicate)
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.bookFingerprintKey == fp.canonicalKey)
    }

    @Test("saveSession updates existing session")
    func saveSessionUpdates() throws {
        let container = try makeContainer()
        let store = SwiftDataSessionStore(modelContainer: container)
        let fp = makeFingerprint()
        let session = ReadingSession(bookFingerprint: fp, startedAt: Date(), deviceId: "test")

        try store.saveSession(session)

        // Update duration and save again
        session.updateDuration(120)
        session.endedAt = Date()
        try store.saveSession(session)

        // Should still be one session, with updated duration
        let context = ModelContext(container)
        let sid = session.sessionId
        let predicate = #Predicate<ReadingSession> { $0.sessionId == sid }
        let fetched = try context.fetch(FetchDescriptor<ReadingSession>(predicate: predicate))
        #expect(fetched.count == 1)
        #expect(fetched.first?.durationSeconds == 120)
        #expect(fetched.first?.endedAt != nil)
    }

    // MARK: - discardSession

    @Test("discardSession removes session by ID")
    func discardSessionRemoves() throws {
        let container = try makeContainer()
        let store = SwiftDataSessionStore(modelContainer: container)
        let fp = makeFingerprint()
        let session = ReadingSession(bookFingerprint: fp, startedAt: Date(), deviceId: "test")

        try store.saveSession(session)
        try store.discardSession(id: session.sessionId)

        // Verify deleted
        let context = ModelContext(container)
        let sid = session.sessionId
        let predicate = #Predicate<ReadingSession> { $0.sessionId == sid }
        let fetched = try context.fetch(FetchDescriptor<ReadingSession>(predicate: predicate))
        #expect(fetched.isEmpty)
    }

    @Test("discardSession no-op for nonexistent ID")
    func discardSessionNoop() throws {
        let container = try makeContainer()
        let store = SwiftDataSessionStore(modelContainer: container)
        // Should not throw
        try store.discardSession(id: UUID())
    }

    // MARK: - flushDuration

    @Test("flushDuration updates duration for existing session")
    func flushDurationUpdates() throws {
        let container = try makeContainer()
        let store = SwiftDataSessionStore(modelContainer: container)
        let fp = makeFingerprint()
        let session = ReadingSession(bookFingerprint: fp, startedAt: Date(), deviceId: "test")

        try store.saveSession(session)
        try store.flushDuration(sessionId: session.sessionId, durationSeconds: 300)

        let context = ModelContext(container)
        let sid = session.sessionId
        let predicate = #Predicate<ReadingSession> { $0.sessionId == sid }
        let fetched = try context.fetch(FetchDescriptor<ReadingSession>(predicate: predicate))
        #expect(fetched.first?.durationSeconds == 300)
    }

    // MARK: - fetchUnclosedSessions

    @Test("fetchUnclosedSessions returns sessions with nil endedAt")
    func fetchUnclosedSessions() throws {
        let container = try makeContainer()
        let store = SwiftDataSessionStore(modelContainer: container)
        let fp = makeFingerprint()

        let open1 = ReadingSession(bookFingerprint: fp, startedAt: Date(), deviceId: "test")
        let open2 = ReadingSession(bookFingerprint: fp, startedAt: Date(), deviceId: "test")
        let closed = ReadingSession(
            bookFingerprint: fp, startedAt: Date(),
            endedAt: Date(), durationSeconds: 60, deviceId: "test"
        )

        try store.saveSession(open1)
        try store.saveSession(open2)
        try store.saveSession(closed)

        let unclosed = try store.fetchUnclosedSessions()
        #expect(unclosed.count == 2)
        let ids = Set(unclosed.map(\.sessionId))
        #expect(ids.contains(open1.sessionId))
        #expect(ids.contains(open2.sessionId))
        #expect(!ids.contains(closed.sessionId))
    }

    @Test("fetchUnclosedSessions returns empty when all sessions closed")
    func fetchUnclosedSessionsEmpty() throws {
        let container = try makeContainer()
        let store = SwiftDataSessionStore(modelContainer: container)
        let fp = makeFingerprint()

        let closed = ReadingSession(
            bookFingerprint: fp, startedAt: Date(),
            endedAt: Date(), durationSeconds: 30, deviceId: "test"
        )
        try store.saveSession(closed)

        let unclosed = try store.fetchUnclosedSessions()
        #expect(unclosed.isEmpty)
    }
}
