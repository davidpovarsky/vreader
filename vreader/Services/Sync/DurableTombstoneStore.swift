// Purpose: JSON-file-backed tombstone store for durable persistence across app restarts.
// Uses a simple tombstones.json file in the specified directory.
//
// Key decisions:
// - Actor isolation for thread safety (no explicit locks needed).
// - Lazy load: file is read on first access, not at init.
// - Write-through: every mutation immediately writes the full file.
// - Graceful recovery: corrupt or empty files produce an empty store (no crash).
// - JSON (not SwiftData) to avoid schema migration complexity.
// - Does not conform to TombstonePersisting (protocol uses mutating, incompatible with actor).
//   Provides the same interface as async methods.
//
// @coordinates-with: SyncTypes.swift, TombstoneStore.swift

import Foundation

// MARK: - Codable wrapper

/// Codable representation of a Tombstone for JSON serialization.
/// Separated from the core Tombstone type to avoid modifying existing files.
struct CodableTombstone: Codable, Sendable {
    let entityType: String
    let entityId: String
    let deletedAt: Date
    let deviceId: String

    init(from tombstone: Tombstone) {
        self.entityType = tombstone.entityType.rawValue
        self.entityId = tombstone.entityId
        self.deletedAt = tombstone.deletedAt
        self.deviceId = tombstone.deviceId
    }

    func toTombstone() -> Tombstone? {
        guard let type = TombstoneEntityType(rawValue: entityType) else { return nil }
        return Tombstone(
            entityType: type,
            entityId: entityId,
            deletedAt: deletedAt,
            deviceId: deviceId
        )
    }
}

// MARK: - Composite key (mirrors InMemoryTombstoneStore's private TombstoneKey)

private struct DurableTombstoneKey: Hashable, Sendable {
    let entityType: TombstoneEntityType
    let entityId: String
}

// MARK: - Actor

/// Durable tombstone store backed by a JSON file.
/// Thread-safe via Swift actor isolation. Lazy-loads on first access.
actor DurableTombstoneStore {

    private let fileURL: URL
    private var tombstones: [DurableTombstoneKey: Tombstone]?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a store that persists to `tombstones.json` in the given directory.
    /// The directory must already exist (or will be created by the caller).
    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("tombstones.json")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public interface

    /// Adds a tombstone. If one already exists for the same entity, keeps the later date.
    func addTombstone(
        entityType: TombstoneEntityType,
        entityId: String,
        deviceId: String,
        deletedAt: Date
    ) {
        ensureLoaded()
        let key = DurableTombstoneKey(entityType: entityType, entityId: entityId)
        if let existing = tombstones![key], existing.deletedAt >= deletedAt {
            return // Keep the later date
        }
        tombstones![key] = Tombstone(
            entityType: entityType,
            entityId: entityId,
            deletedAt: deletedAt,
            deviceId: deviceId
        )
        writeToDisk()
    }

    /// Checks if a tombstone exists for the given entity.
    func hasTombstone(
        entityType: TombstoneEntityType,
        entityId: String
    ) -> (exists: Bool, deletedAt: Date?) {
        ensureLoaded()
        let key = DurableTombstoneKey(entityType: entityType, entityId: entityId)
        guard let tombstone = tombstones![key] else {
            return (false, nil)
        }
        return (true, tombstone.deletedAt)
    }

    /// Removes tombstones older than the cutoff date. Returns the count of purged items.
    @discardableResult
    func purgeTombstones(olderThan cutoff: Date) -> Int {
        ensureLoaded()
        let keysToPurge = tombstones!.filter { $0.value.deletedAt < cutoff }.map(\.key)
        for key in keysToPurge {
            tombstones!.removeValue(forKey: key)
        }
        if !keysToPurge.isEmpty {
            writeToDisk()
        }
        return keysToPurge.count
    }

    /// The total number of tombstones in the store.
    var count: Int {
        ensureLoaded()
        return tombstones!.count
    }

    /// All tombstones currently in the store.
    var allTombstones: [Tombstone] {
        ensureLoaded()
        return Array(tombstones!.values)
    }

    // MARK: - Private

    /// Lazily loads the tombstones from disk on first access.
    private func ensureLoaded() {
        guard tombstones == nil else { return }
        tombstones = loadFromDisk()
    }

    /// Last I/O error (audit fix: surface errors instead of swallowing).
    private(set) var lastError: Error?

    /// Reads and decodes the JSON file. Returns empty dict on any failure.
    private func loadFromDisk() -> [DurableTombstoneKey: Tombstone] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return [:] }
            let codables = try decoder.decode([CodableTombstone].self, from: data)
            var result: [DurableTombstoneKey: Tombstone] = [:]
            for c in codables {
                guard let tombstone = c.toTombstone() else { continue }
                let key = DurableTombstoneKey(entityType: tombstone.entityType, entityId: tombstone.entityId)
                result[key] = tombstone
            }
            lastError = nil
            return result
        } catch {
            lastError = error
            return [:]
        }
    }

    /// Encodes and writes all tombstones to disk.
    /// Stores error in lastError on failure (audit fix: surface I/O errors).
    private func writeToDisk() {
        guard let tombstones = tombstones else { return }
        let codables = tombstones.values.map { CodableTombstone(from: $0) }
        do {
            let data = try encoder.encode(codables)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error
        }
    }
}
