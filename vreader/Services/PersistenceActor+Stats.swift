// Purpose: Extension adding reading stats recomputation to PersistenceActor.
// Aggregates ReadingSession records into a ReadingStats record per book.
//
// Key decisions:
// - Upserts ReadingStats: creates if missing, updates if exists.
// - Recomputes all aggregate fields from sessions (idempotent).
// - Called after session end so library sorting by reading time/last read works.
//
// @coordinates-with: PersistenceActor.swift, ReadingStats.swift, ReadingSession.swift

import Foundation
import SwiftData

extension PersistenceActor {

    /// Recomputes the ReadingStats record for a book from all its ReadingSession records.
    /// Creates the stats record if it doesn't exist yet (upsert).
    func recomputeStats(bookFingerprintKey: String, bookFingerprint: DocumentFingerprint) async throws {
        let context = ModelContext(modelContainer)

        // Fetch all sessions for this book
        let key = bookFingerprintKey
        let sessionPredicate = #Predicate<ReadingSession> {
            $0.bookFingerprintKey == key
        }
        let sessions = try context.fetch(
            FetchDescriptor<ReadingSession>(predicate: sessionPredicate)
        )

        // Find or create stats record
        let statsPredicate = #Predicate<ReadingStats> {
            $0.bookFingerprintKey == key
        }
        var statsDescriptor = FetchDescriptor<ReadingStats>(predicate: statsPredicate)
        statsDescriptor.fetchLimit = 1

        let stats: ReadingStats
        if let existing = try context.fetch(statsDescriptor).first {
            stats = existing
        } else {
            stats = ReadingStats(bookFingerprint: bookFingerprint)
            context.insert(stats)
        }

        stats.recompute(from: sessions)
        try context.save()
    }
}
