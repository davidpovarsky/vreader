// Purpose: Tests for ChangeTokenStore — save, load, clear, nil-on-first-use, multiple zones.

import Testing
import Foundation
@testable import vreader

@Suite("ChangeTokenStore")
struct ChangeTokenStoreTests {

    /// Creates a fresh UserDefaults suite for test isolation.
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "com.vreader.test.changeToken.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    // MARK: - Nil On First Use

    @Test func loadReturnsNilWhenNeverSaved() {
        let defaults = makeIsolatedDefaults()
        let store = ChangeTokenStore(defaults: defaults)
        let token = store.load(forZone: "VReaderData")
        #expect(token == nil)
    }

    // MARK: - Save and Load

    @Test func saveAndLoadRoundTrip() {
        let defaults = makeIsolatedDefaults()
        let store = ChangeTokenStore(defaults: defaults)
        let tokenData = Data("server-change-token-v1".utf8)

        store.save(token: tokenData, forZone: "VReaderData")
        let loaded = store.load(forZone: "VReaderData")
        #expect(loaded == tokenData)
    }

    @Test func overwriteExistingToken() {
        let defaults = makeIsolatedDefaults()
        let store = ChangeTokenStore(defaults: defaults)

        let firstToken = Data("token-v1".utf8)
        let secondToken = Data("token-v2".utf8)

        store.save(token: firstToken, forZone: "VReaderData")
        store.save(token: secondToken, forZone: "VReaderData")

        let loaded = store.load(forZone: "VReaderData")
        #expect(loaded == secondToken)
    }

    // MARK: - Clear

    @Test func clearRemovesToken() {
        let defaults = makeIsolatedDefaults()
        let store = ChangeTokenStore(defaults: defaults)

        store.save(token: Data("token".utf8), forZone: "VReaderData")
        store.clear(forZone: "VReaderData")

        let loaded = store.load(forZone: "VReaderData")
        #expect(loaded == nil)
    }

    @Test func clearNonexistentZoneIsNoOp() {
        let defaults = makeIsolatedDefaults()
        let store = ChangeTokenStore(defaults: defaults)
        // Should not crash
        store.clear(forZone: "NonExistentZone")
        let loaded = store.load(forZone: "NonExistentZone")
        #expect(loaded == nil)
    }

    // MARK: - Multiple Zones

    @Test func differentZonesAreIndependent() {
        let defaults = makeIsolatedDefaults()
        let store = ChangeTokenStore(defaults: defaults)

        let tokenA = Data("zone-a-token".utf8)
        let tokenB = Data("zone-b-token".utf8)

        store.save(token: tokenA, forZone: "ZoneA")
        store.save(token: tokenB, forZone: "ZoneB")

        #expect(store.load(forZone: "ZoneA") == tokenA)
        #expect(store.load(forZone: "ZoneB") == tokenB)
    }

    @Test func clearOneZoneDoesNotAffectOther() {
        let defaults = makeIsolatedDefaults()
        let store = ChangeTokenStore(defaults: defaults)

        store.save(token: Data("a".utf8), forZone: "ZoneA")
        store.save(token: Data("b".utf8), forZone: "ZoneB")

        store.clear(forZone: "ZoneA")

        #expect(store.load(forZone: "ZoneA") == nil)
        #expect(store.load(forZone: "ZoneB") == Data("b".utf8))
    }

    // MARK: - Empty Zone Name

    @Test func emptyZoneNameWorks() {
        let defaults = makeIsolatedDefaults()
        let store = ChangeTokenStore(defaults: defaults)

        let token = Data("token".utf8)
        store.save(token: token, forZone: "")
        #expect(store.load(forZone: "") == token)
    }

    // MARK: - Empty Token Data

    @Test func emptyDataCanBeSavedAndLoaded() {
        let defaults = makeIsolatedDefaults()
        let store = ChangeTokenStore(defaults: defaults)

        store.save(token: Data(), forZone: "VReaderData")
        let loaded = store.load(forZone: "VReaderData")
        #expect(loaded == Data())
    }

    // MARK: - Key Prefix

    @Test func usesCorrectKeyPrefix() {
        let defaults = makeIsolatedDefaults()
        let store = ChangeTokenStore(defaults: defaults)

        store.save(token: Data("t".utf8), forZone: "VReaderData")

        // Verify the key is stored with the expected prefix
        let rawValue = defaults.data(forKey: "ck_changeToken_VReaderData")
        #expect(rawValue == Data("t".utf8))
    }
}
