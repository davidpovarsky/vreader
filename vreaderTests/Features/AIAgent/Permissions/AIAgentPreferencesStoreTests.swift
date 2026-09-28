import Foundation
import Testing
@testable import vreader

@Suite("Feature #177 WI-5 — agent preferences persistence")
struct AIAgentPreferencesStoreTests {
    private static func makeStore(
        key: String = "tests.ai-agent-preferences"
    ) -> (AIAgentPreferencesStore, MockPreferenceStore) {
        let preferences = MockPreferenceStore()
        return (
            AIAgentPreferencesStore(preferences: preferences, storageKey: key),
            preferences
        )
    }

    @Test("defaults are deterministic")
    func deterministicDefaults() async {
        let (first, _) = Self.makeStore()
        let (second, _) = Self.makeStore()

        #expect(await first.load() == await second.load())
        #expect(await first.load() == .default)
    }

    @Test("read-ahead defaults to never")
    func defaultReadAheadMode() async {
        let (store, _) = Self.makeStore()
        #expect(await store.load().readAheadMode == .neverReadAhead)
    }

    @Test("a permission decision round-trips")
    func permissionRoundTrip() async {
        let (store, _) = Self.makeStore()
        await store.setDecision(.deny, for: .externalNetwork)

        #expect(await store.load().decision(for: .externalNetwork) == .deny)
    }

    @Test("read-ahead mode round-trips")
    func readAheadModeRoundTrip() async {
        let (store, _) = Self.makeStore()
        await store.setReadAheadMode(.wholeBookAllowed)

        #expect(await store.load().readAheadMode == .wholeBookAllowed)
    }

    @Test("updating one preference preserves every unrelated value")
    func individualUpdatePreservesOtherValues() async {
        let (store, _) = Self.makeStore()
        await store.setDecision(.deny, for: .readOtherBooks)
        await store.setReadAheadMode(.askBeforeReadingAhead)
        await store.setDecision(.allow, for: .navigateReader)

        let loaded = await store.load()
        #expect(loaded.decision(for: .readOtherBooks) == .deny)
        #expect(loaded.decision(for: .navigateReader) == .allow)
        #expect(loaded.readAheadMode == .askBeforeReadingAhead)
    }

    @Test("missing and future persisted values decode safely")
    func olderPersistedValuesDecodeSafely() async {
        let key = "tests.older-agent-preferences"
        let (store, preferences) = Self.makeStore(key: key)
        preferences.setRaw(
            #"{"permissions":{"readCurrentBook":"deny","futureCategory":"futureValue"}}"#,
            forKey: key
        )

        let loaded = await store.load()
        #expect(loaded.decision(for: .readCurrentBook) == .deny)
        #expect(
            loaded.decision(for: .writeAnnotations)
                == AIAgentPreferences.default.decision(for: .writeAnnotations)
        )
        #expect(loaded.readAheadMode == .neverReadAhead)
    }

    @Test("isolated stores do not leak values")
    func isolatedStoresDoNotLeak() async {
        let (first, _) = Self.makeStore()
        let (second, _) = Self.makeStore()
        await first.setDecision(.deny, for: .readCurrentBook)

        #expect(await first.load().decision(for: .readCurrentBook) == .deny)
        #expect(await second.load().decision(for: .readCurrentBook) == .allow)
    }
}
