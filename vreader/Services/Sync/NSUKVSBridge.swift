// Purpose: Bridges UserDefaults ↔ NSUbiquitousKeyValueStore for a fixed set of synced keys.
// Only the 5 keys in `syncedKeys` are ever read from or written to the cloud store.
//
// Key decisions:
// - CloudKeyValueStore protocol enables testing without real NSUKVS.
// - @MainActor because UserDefaults notifications arrive on main and UI
//   state updates (PreferenceStore) must happen on main.
// - pullAll skips nil cloud values to avoid overwriting local defaults with nothing.
// - pushAll writes nil for missing local values to clear stale cloud entries.
// - handleExternalChange uses a reverse lookup (cloud key → local key) for efficiency.
// - synchronize() is called after every write batch per Apple recommendation.
//
// @coordinates-with: DeviceIdentity.swift, SyncService.swift

import Foundation

// MARK: - Protocol

/// Abstraction over NSUbiquitousKeyValueStore for testability.
protocol CloudKeyValueStore: AnyObject, Sendable {
    /// Returns the string value for the given key, or nil.
    func string(forKey key: String) -> String?

    /// Sets a string value (or nil to remove) for the given key.
    func set(_ value: String?, forKey key: String)

    /// Requests an immediate synchronization. Returns true on success.
    @discardableResult
    func synchronize() -> Bool
}

// MARK: - NSUbiquitousKeyValueStore Conformance

// NSUbiquitousKeyValueStore is thread-safe per Apple docs.
// @unchecked Sendable satisfies the protocol's Sendable constraint.
// @retroactive because Sendable is from the stdlib, not our module.
extension NSUbiquitousKeyValueStore: CloudKeyValueStore, @retroactive @unchecked Sendable {
    // NSUbiquitousKeyValueStore already has matching method signatures:
    //   func string(forKey key: String) -> String?
    //   func set(_ aString: String?, forKey aKey: String)
    //   func synchronize() -> Bool
    // No additional implementation needed — the protocol is satisfied.
}

// MARK: - Bridge

/// Bridges UserDefaults ↔ CloudKeyValueStore for a fixed set of synced keys.
@MainActor
final class NSUKVSBridge {

    /// Maps local UserDefaults key → cloud (NSUKVS) key.
    /// Only these 5 keys are ever synced.
    static let syncedKeys: [String: String] = [
        "librarySortOrder": "library.sortOrder",
        "libraryViewMode": "library.viewMode",
        "readerTheme": "reader.theme",
        "aiEnabled": "ai.enabled",
        "syncSchemaVersion": "schemaVersion",
    ]

    /// Reverse map: cloud key → local key (computed once).
    private static let reversedKeys: [String: String] = {
        Dictionary(uniqueKeysWithValues: syncedKeys.map { ($0.value, $0.key) })
    }()

    private let local: UserDefaults
    private let cloud: CloudKeyValueStore

    // MARK: - Init

    /// Creates a bridge between local UserDefaults and a cloud key-value store.
    ///
    /// - Parameters:
    ///   - local: The UserDefaults instance to read/write local values.
    ///   - cloud: The cloud key-value store (real NSUKVS or mock).
    init(local: UserDefaults, cloud: CloudKeyValueStore) {
        self.local = local
        self.cloud = cloud
    }

    // MARK: - Push

    /// Pushes all synced key values from local to cloud.
    func pushAll() {
        for (localKey, cloudKey) in Self.syncedKeys {
            let value = local.string(forKey: localKey)
            cloud.set(value, forKey: cloudKey)
        }
        cloud.synchronize()
    }

    /// Pushes a single key to cloud if it is in the synced set.
    /// No-op for non-synced keys.
    func pushIfSynced(localKey: String) {
        guard let cloudKey = Self.syncedKeys[localKey] else { return }
        let value = local.string(forKey: localKey)
        cloud.set(value, forKey: cloudKey)
        cloud.synchronize()
    }

    // MARK: - Pull

    /// Pulls all synced key values from cloud to local.
    /// Skips keys where the cloud value is nil (preserves local value).
    func pullAll() {
        for (localKey, cloudKey) in Self.syncedKeys {
            if let cloudValue = cloud.string(forKey: cloudKey) {
                local.set(cloudValue, forKey: localKey)
            }
            // If cloud has no value, do not overwrite local.
        }
    }

    // MARK: - External Change

    /// Handles external change notifications from NSUbiquitousKeyValueStore.
    /// Only updates local values for keys that are in the synced set AND
    /// appear in the changedKeys list.
    ///
    /// - Parameter changedKeys: The cloud keys reported as changed.
    func handleExternalChange(changedKeys: [String]) {
        for cloudKey in changedKeys {
            guard let localKey = Self.reversedKeys[cloudKey] else { continue }
            if let cloudValue = cloud.string(forKey: cloudKey) {
                local.set(cloudValue, forKey: localKey)
            } else {
                // Audit fix: propagate cloud deletions to local
                local.removeObject(forKey: localKey)
            }
        }
    }
}
