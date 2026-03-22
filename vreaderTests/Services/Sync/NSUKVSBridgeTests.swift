// Purpose: Tests for NSUKVSBridge — UserDefaults ↔ cloud key-value store sync bridge.
// Uses MockCloudKeyValueStore to test without real NSUbiquitousKeyValueStore.

import Testing
import Foundation
@testable import vreader

// MARK: - Mock

/// In-memory mock of CloudKeyValueStore for deterministic testing.
final class MockCloudKeyValueStore: CloudKeyValueStore, @unchecked Sendable {
    private var storage: [String: String?] = [:]
    private(set) var synchronizeCallCount = 0

    func string(forKey key: String) -> String? {
        storage[key] ?? nil
    }

    func set(_ value: String?, forKey key: String) {
        storage[key] = value
    }

    func synchronize() -> Bool {
        synchronizeCallCount += 1
        return true
    }

    /// Expose storage for test assertions.
    func allKeys() -> [String] {
        Array(storage.keys)
    }

    /// Check if a specific key was ever written.
    func hasKey(_ key: String) -> Bool {
        storage.keys.contains(key)
    }

    /// Direct access for test setup.
    subscript(key: String) -> String? {
        get { storage[key] ?? nil }
        set { storage[key] = newValue }
    }
}

// MARK: - Tests

@Suite("NSUKVSBridge")
@MainActor
struct NSUKVSBridgeTests {

    /// Creates fresh local + cloud stores for each test.
    private func makeBridge() -> (bridge: NSUKVSBridge, local: UserDefaults, cloud: MockCloudKeyValueStore) {
        let suiteName = "com.vreader.test.nsukvs.\(UUID().uuidString)"
        let local = UserDefaults(suiteName: suiteName)!
        let cloud = MockCloudKeyValueStore()
        let bridge = NSUKVSBridge(local: local, cloud: cloud)
        return (bridge, local, cloud)
    }

    // MARK: - pushAll

    @Test @MainActor func pushAllMirrorsAllSyncedKeysToCloud() {
        let (bridge, local, cloud) = makeBridge()

        // Set all 5 synced local keys
        local.set("title", forKey: "librarySortOrder")
        local.set("grid", forKey: "libraryViewMode")
        local.set("sepia", forKey: "readerTheme")
        local.set("true", forKey: "aiEnabled")
        local.set("4", forKey: "syncSchemaVersion")

        bridge.pushAll()

        #expect(cloud.string(forKey: "library.sortOrder") == "title")
        #expect(cloud.string(forKey: "library.viewMode") == "grid")
        #expect(cloud.string(forKey: "reader.theme") == "sepia")
        #expect(cloud.string(forKey: "ai.enabled") == "true")
        #expect(cloud.string(forKey: "schemaVersion") == "4")
    }

    @Test @MainActor func pushAllCallsSynchronize() {
        let (bridge, _, cloud) = makeBridge()
        bridge.pushAll()
        #expect(cloud.synchronizeCallCount == 1)
    }

    // MARK: - pullAll

    @Test @MainActor func pullAllMirrorsCloudValuesToLocal() {
        let (bridge, local, cloud) = makeBridge()

        // Set cloud values
        cloud["library.sortOrder"] = "author"
        cloud["library.viewMode"] = "list"
        cloud["reader.theme"] = "dark"
        cloud["ai.enabled"] = "false"
        cloud["schemaVersion"] = "5"

        bridge.pullAll()

        #expect(local.string(forKey: "librarySortOrder") == "author")
        #expect(local.string(forKey: "libraryViewMode") == "list")
        #expect(local.string(forKey: "readerTheme") == "dark")
        #expect(local.string(forKey: "aiEnabled") == "false")
        #expect(local.string(forKey: "syncSchemaVersion") == "5")
    }

    // MARK: - pushIfSynced

    @Test @MainActor func pushIfSyncedPushesSyncedKey() {
        let (bridge, local, cloud) = makeBridge()
        local.set("title", forKey: "librarySortOrder")

        bridge.pushIfSynced(localKey: "librarySortOrder")

        #expect(cloud.string(forKey: "library.sortOrder") == "title")
    }

    @Test @MainActor func pushIfSyncedIgnoresNonSyncedKey() {
        let (bridge, local, cloud) = makeBridge()
        local.set("something", forKey: "unrelatedKey")

        bridge.pushIfSynced(localKey: "unrelatedKey")

        // Nothing should be written to cloud
        #expect(cloud.allKeys().isEmpty, "Non-synced keys must not be written to cloud")
    }

    @Test @MainActor func pushIfSyncedCallsSynchronizeForSyncedKey() {
        let (bridge, local, cloud) = makeBridge()
        local.set("grid", forKey: "libraryViewMode")

        bridge.pushIfSynced(localKey: "libraryViewMode")

        #expect(cloud.synchronizeCallCount == 1)
    }

    @Test @MainActor func pushIfSyncedDoesNotCallSynchronizeForNonSyncedKey() {
        let (bridge, _, cloud) = makeBridge()

        bridge.pushIfSynced(localKey: "randomKey")

        #expect(cloud.synchronizeCallCount == 0)
    }

    // MARK: - handleExternalChange

    @Test @MainActor func handleExternalChangeUpdatesLocalForSyncedKeys() {
        let (bridge, local, cloud) = makeBridge()

        // Simulate cloud update
        cloud["library.sortOrder"] = "date"
        cloud["reader.theme"] = "night"

        bridge.handleExternalChange(changedKeys: ["library.sortOrder", "reader.theme"])

        #expect(local.string(forKey: "librarySortOrder") == "date")
        #expect(local.string(forKey: "readerTheme") == "night")
    }

    @Test @MainActor func handleExternalChangeIgnoresNonSyncedCloudKeys() {
        let (bridge, local, cloud) = makeBridge()

        cloud["some.random.key"] = "value"
        bridge.handleExternalChange(changedKeys: ["some.random.key"])

        // local should not have any new keys from this
        #expect(local.string(forKey: "some.random.key") == nil)
    }

    @Test @MainActor func handleExternalChangeWithEmptyKeysIsNoOp() {
        let (bridge, local, _) = makeBridge()
        local.set("original", forKey: "librarySortOrder")

        bridge.handleExternalChange(changedKeys: [])

        #expect(local.string(forKey: "librarySortOrder") == "original")
    }

    // MARK: - Edge Case: Missing Cloud Value

    @Test @MainActor func pullAllPreservesLocalWhenCloudValueIsMissing() {
        let (bridge, local, _) = makeBridge()

        // Set a local value but leave cloud empty
        local.set("original-sort", forKey: "librarySortOrder")

        bridge.pullAll()

        // Local value must be preserved when cloud has no value
        #expect(local.string(forKey: "librarySortOrder") == "original-sort")
    }

    // MARK: - Edge Case: Nil Local Value

    @Test @MainActor func pushAllWritesNilToCloudWhenLocalIsMissing() {
        let (bridge, _, cloud) = makeBridge()

        // Pre-set a cloud value
        cloud["library.sortOrder"] = "old-value"

        // Push with no local values set — should write nil
        bridge.pushAll()

        #expect(cloud.string(forKey: "library.sortOrder") == nil)
    }

    // MARK: - Edge Case: Empty String Values

    @Test @MainActor func pushAllHandlesEmptyStringValues() {
        let (bridge, local, cloud) = makeBridge()
        local.set("", forKey: "librarySortOrder")

        bridge.pushAll()

        #expect(cloud.string(forKey: "library.sortOrder") == "")
    }

    @Test @MainActor func pullAllHandlesEmptyStringValues() {
        let (bridge, local, cloud) = makeBridge()
        cloud["library.sortOrder"] = ""

        bridge.pullAll()

        #expect(local.string(forKey: "librarySortOrder") == "")
    }

    // MARK: - Non-Synced Keys Never Written

    @Test @MainActor func nonSyncedLocalKeysNeverAppearInCloud() {
        let (bridge, local, cloud) = makeBridge()

        // Set both synced and non-synced keys
        local.set("grid", forKey: "libraryViewMode")
        local.set("secret", forKey: "apiKey")
        local.set("private", forKey: "userPassword")

        bridge.pushAll()

        // Only the mapped cloud key should exist
        #expect(cloud.string(forKey: "library.viewMode") == "grid")
        #expect(cloud.hasKey("apiKey") == false)
        #expect(cloud.hasKey("userPassword") == false)
    }

    // MARK: - Synced Keys Map Completeness

    @Test func syncedKeysContainsFiveEntries() {
        #expect(NSUKVSBridge.syncedKeys.count == 5)
    }

    @Test func syncedKeysContainsExpectedLocalKeys() {
        let expectedLocalKeys: Set<String> = [
            "librarySortOrder",
            "libraryViewMode",
            "readerTheme",
            "aiEnabled",
            "syncSchemaVersion"
        ]
        #expect(Set(NSUKVSBridge.syncedKeys.keys) == expectedLocalKeys)
    }

    @Test func syncedKeysContainsExpectedCloudKeys() {
        let expectedCloudKeys: Set<String> = [
            "library.sortOrder",
            "library.viewMode",
            "reader.theme",
            "ai.enabled",
            "schemaVersion"
        ]
        #expect(Set(NSUKVSBridge.syncedKeys.values) == expectedCloudKeys)
    }

    // MARK: - handleExternalChange Partial Updates

    @Test @MainActor func handleExternalChangeOnlyUpdatesChangedKeys() {
        let (bridge, local, cloud) = makeBridge()

        // Pre-set local values
        local.set("title", forKey: "librarySortOrder")
        local.set("grid", forKey: "libraryViewMode")

        // Cloud has a different sort order but same view mode
        cloud["library.sortOrder"] = "author"
        cloud["library.viewMode"] = "list"

        // Only notify about sortOrder change
        bridge.handleExternalChange(changedKeys: ["library.sortOrder"])

        #expect(local.string(forKey: "librarySortOrder") == "author", "Changed key should be updated")
        #expect(local.string(forKey: "libraryViewMode") == "grid", "Unchanged key should be preserved")
    }
}
