// Purpose: SwiftData-backed SessionPersisting implementation.
// Replaces NoOpSessionStore so reading sessions are actually persisted.
//
// Key decisions:
// - @MainActor for protocol conformance (SessionPersisting is @MainActor).
// - Fresh ModelContext per operation for isolation from other writes.
// - Uses sessionId @Attribute(.unique) for safe upsert semantics.
//
// @coordinates-with: ReadingSessionTracker.swift, ReadingSession.swift,
//   PersistenceActor.swift

import Foundation
import SwiftData

/// Persists reading sessions via SwiftData.
@MainActor
final class SwiftDataSessionStore: SessionPersisting {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func saveSession(_ session: ReadingSession) throws {
        let context = ModelContext(modelContainer)
        let sid = session.sessionId
        let predicate = #Predicate<ReadingSession> { $0.sessionId == sid }
        var descriptor = FetchDescriptor<ReadingSession>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            // Update in place
            existing.endedAt = session.endedAt
            existing.updateDuration(session.durationSeconds)
            existing.updatePagesRead(session.pagesRead)
            existing.updateWordsRead(session.wordsRead)
            existing.endLocator = session.endLocator
            existing.isRecovered = session.isRecovered
        } else {
            context.insert(session)
        }
        try context.save()
    }

    func discardSession(id: UUID) throws {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<ReadingSession> { $0.sessionId == id }
        var descriptor = FetchDescriptor<ReadingSession>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            context.delete(existing)
            try context.save()
        }
    }

    func flushDuration(sessionId: UUID, durationSeconds: Int) throws {
        let context = ModelContext(modelContainer)
        let sid = sessionId
        let predicate = #Predicate<ReadingSession> { $0.sessionId == sid }
        var descriptor = FetchDescriptor<ReadingSession>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.updateDuration(durationSeconds)
            try context.save()
        }
    }

    func fetchUnclosedSessions() throws -> [ReadingSession] {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<ReadingSession> { $0.endedAt == nil }
        let descriptor = FetchDescriptor<ReadingSession>(predicate: predicate)
        return try context.fetch(descriptor)
    }
}
