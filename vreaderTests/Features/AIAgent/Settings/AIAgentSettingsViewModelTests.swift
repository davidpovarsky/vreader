// Purpose: Unit tests for AIAgentSettingsViewModel.
// Validates permission updates, "Always ask" invariant on data deletion, and capability toggles.

import Testing
import Foundation
@testable import vreader

@Suite("AIAgentSettingsViewModelTests")
struct AIAgentSettingsViewModelTests {

    @Test func deletionAlwaysRemainsAsk() {
        let store = InMemoryAIAgentPreferencesStore()
        let vm = AIAgentSettingsViewModel(preferencesStore: store)

        // Attempting to set removeData to allow must be blocked or ignored
        vm.setPermission(.removeData, policy: .allow)

        #expect(vm.permission(for: .removeData) == .ask)
        #expect(store.preferences.permissions[.removeData] == .ask)
    }

    @Test func permissionChangesPersistToStore() {
        let store = InMemoryAIAgentPreferencesStore()
        let vm = AIAgentSettingsViewModel(preferencesStore: store)

        vm.setPermission(.writeAnnotations, policy: .allow)
        #expect(vm.permission(for: .writeAnnotations) == .allow)
        #expect(store.preferences.permissions[.writeAnnotations] == .allow)

        vm.setPermission(.writeAnnotations, policy: .deny)
        #expect(vm.permission(for: .writeAnnotations) == .deny)
        #expect(store.preferences.permissions[.writeAnnotations] == .deny)
    }

    @Test func readAheadModeChangesPersistToStore() {
        let store = InMemoryAIAgentPreferencesStore()
        let vm = AIAgentSettingsViewModel(preferencesStore: store)

        vm.setReadAheadMode(.wholeBookAllowed)
        #expect(vm.readAheadMode == .wholeBookAllowed)
        #expect(store.preferences.readAheadMode == .wholeBookAllowed)

        vm.setReadAheadMode(.neverReadAhead)
        #expect(vm.readAheadMode == .neverReadAhead)
        #expect(store.preferences.readAheadMode == .neverReadAhead)
    }

    @Test func capabilityTogglesAreIndependent() {
        let prefs = AIAgentCapabilityPreferences()
        prefs.isSemanticSearchEnabled = true
        prefs.isOCREnabled = false

        #expect(prefs.isSemanticSearchEnabled == true)
        #expect(prefs.isOCREnabled == false)

        prefs.isOCREnabled = true
        #expect(prefs.isOCREnabled == true)
    }
}
