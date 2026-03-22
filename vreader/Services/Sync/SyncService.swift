// Purpose: Coordinates sync operations for the vreader app.
// All operations are guarded by FeatureFlags.sync — when OFF, everything is a no-op.
// Delegates to SyncConflictResolver for merge decisions and
// FileAvailabilityStateMachine for file state transitions.
//
// Key decisions:
// - Actor-isolated for thread safety.
// - Feature flag check is the first guard in every public method.
// - CloudKit integration is deferred; this layer handles conflict resolution
//   and state management above SwiftData.
// - File availability is tracked per-book in an in-memory dictionary.
//
// @coordinates-with: SyncTypes.swift, SyncConflictResolver.swift,
//   FileAvailabilityStateMachine.swift, SyncStatusMonitor.swift, FeatureFlags.swift

import Foundation

/// Coordinates sync operations across the app.
/// All operations are no-ops when `FeatureFlags.sync` is OFF.
actor SyncService {

    // MARK: - Dependencies

    private let featureFlags: FeatureFlags
    private let conflictResolver: SyncConflictResolver
    private let stateMachine: FileAvailabilityStateMachine
    private let tombstoneStore: DurableTombstoneStore

    /// Per-book file availability state.
    private var fileStates: [String: FileAvailability] = [:]

    /// Current sync status (reflects feature flag state).
    var syncStatus: SyncStatus {
        featureFlags.sync ? .idle : .disabled
    }

    // MARK: - Init

    /// Tombstone retention: 30 days (audit fix: extract from hardcoded inline).
    static let tombstoneRetentionSeconds: TimeInterval = 30 * 24 * 3600

    init(
        featureFlags: FeatureFlags,
        conflictResolver: SyncConflictResolver = SyncConflictResolver(),
        stateMachine: FileAvailabilityStateMachine = FileAvailabilityStateMachine(),
        tombstoneStore: DurableTombstoneStore? = nil
    ) {
        self.featureFlags = featureFlags
        self.conflictResolver = conflictResolver
        self.stateMachine = stateMachine
        self.tombstoneStore = tombstoneStore ?? DurableTombstoneStore(
            directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Sync", isDirectory: true)
        )
    }

    // MARK: - Metadata Sync

    /// Coordinates conflict resolution for all entity types for a given book.
    /// Returns `.disabled` when sync is OFF, `.success` on completion.
    func syncMetadata(for bookFingerprintKey: String) -> SyncOperationResult {
        guard featureFlags.sync else { return .disabled }
        // V2: conflict resolution is handled on-demand when remote changes arrive.
        // This method is the coordination entry point; actual merge happens
        // when CloudKit push notifications deliver remote records.
        return .success
    }

    // MARK: - File Download

    /// Requests a file download for the given book, transitioning its state machine.
    /// Returns `.disabled` when sync is OFF, `.queued` when download is queued.
    func requestFileDownload(bookFingerprintKey: String) -> SyncOperationResult {
        guard featureFlags.sync else { return .disabled }
        let current = fileStates[bookFingerprintKey] ?? .metadataOnly
        let next = stateMachine.transition(from: current, event: .userOpen)
        fileStates[bookFingerprintKey] = next
        return .queued
    }

    // MARK: - File Availability

    /// Returns the current file availability state for a book.
    func fileAvailability(for bookFingerprintKey: String) -> FileAvailability {
        fileStates[bookFingerprintKey] ?? .metadataOnly
    }

    // MARK: - Tombstones

    /// Records a soft-delete tombstone.
    func recordTombstone(
        entityType: TombstoneEntityType,
        entityId: String,
        deviceId: String
    ) async {
        guard featureFlags.sync else { return }
        await tombstoneStore.addTombstone(
            entityType: entityType,
            entityId: entityId,
            deviceId: deviceId,
            deletedAt: Date()
        )
    }

    /// Purges tombstones older than the retention period.
    @discardableResult
    func purgeStaleTombstones() async -> Int {
        guard featureFlags.sync else { return 0 }
        let cutoff = Date().addingTimeInterval(-Self.tombstoneRetentionSeconds)
        return await tombstoneStore.purgeTombstones(olderThan: cutoff)
    }
}
