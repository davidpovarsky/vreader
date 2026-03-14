// Purpose: Tests for LibraryViewModel preference persistence —
// sortOrder and viewMode survive ViewModel recreation.

import Testing
import Foundation
@testable import vreader

@Suite("LibraryViewModel Persistence")
struct LibraryViewModelPersistenceTests {

    // MARK: - Sort Order Persistence

    @Test @MainActor func sortOrderSurvivesRecreation() async {
        let prefs = MockPreferenceStore()
        let mock = MockLibraryPersistence()

        let vm1 = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        vm1.sortOrder = .addedAt

        // Recreate with same PreferenceStore — should restore .addedAt
        let vm2 = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        #expect(vm2.sortOrder == .addedAt, "sortOrder should survive recreation")
    }

    @Test @MainActor func sortOrderPersistsAllValues() async {
        let prefs = MockPreferenceStore()
        let mock = MockLibraryPersistence()

        for order in LibrarySortOrder.allCases {
            let vm = LibraryViewModel(persistence: mock, preferenceStore: prefs)
            vm.sortOrder = order

            let restored = LibraryViewModel(persistence: mock, preferenceStore: prefs)
            #expect(restored.sortOrder == order, "sortOrder \(order) should persist and restore")
        }
    }

    // MARK: - View Mode Persistence

    @Test @MainActor func viewModeSurvivesRecreation() async {
        let prefs = MockPreferenceStore()
        let mock = MockLibraryPersistence()

        let vm1 = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        vm1.viewMode = .list

        let vm2 = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        #expect(vm2.viewMode == .list, "viewMode should survive recreation")
    }

    @Test @MainActor func viewModeTogglePersists() async {
        let prefs = MockPreferenceStore()
        let mock = MockLibraryPersistence()

        let vm1 = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        vm1.toggleViewMode() // grid -> list

        let vm2 = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        #expect(vm2.viewMode == .list, "toggleViewMode should persist the new mode")
    }

    // MARK: - Defaults

    @Test @MainActor func defaultSortOrderIsTitle() {
        let prefs = MockPreferenceStore()
        let mock = MockLibraryPersistence()

        let vm = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        #expect(vm.sortOrder == .title, "Fresh install should default to .title")
    }

    @Test @MainActor func defaultViewModeIsGrid() {
        let prefs = MockPreferenceStore()
        let mock = MockLibraryPersistence()

        let vm = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        #expect(vm.viewMode == .grid, "Fresh install should default to .grid")
    }

    // MARK: - Default Reset Option

    @Test @MainActor func defaultSortOrderResetOption() async {
        let prefs = MockPreferenceStore()
        let mock = MockLibraryPersistence()

        let vm = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        vm.sortOrder = .lastReadAt

        // "Default" option resets to .title
        vm.sortOrder = .title

        let restored = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        #expect(restored.sortOrder == .title, "Reset option should persist .title")
    }

    // MARK: - Corrupted / Unknown Stored Values

    @Test @MainActor func unknownStoredSortOrderFallsBackToDefault() {
        let prefs = MockPreferenceStore()
        prefs.setRaw("invalidSortOrder", forKey: "library.sortOrder")
        let mock = MockLibraryPersistence()

        let vm = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        #expect(vm.sortOrder == .title, "Unknown sort order should fall back to .title")
    }

    @Test @MainActor func unknownStoredViewModeFallsBackToDefault() {
        let prefs = MockPreferenceStore()
        prefs.setRaw("invalidViewMode", forKey: "library.viewMode")
        let mock = MockLibraryPersistence()

        let vm = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        #expect(vm.viewMode == .grid, "Unknown view mode should fall back to .grid")
    }

    @Test @MainActor func emptyStringStoredValueFallsBackToDefault() {
        let prefs = MockPreferenceStore()
        prefs.setRaw("", forKey: "library.sortOrder")
        prefs.setRaw("", forKey: "library.viewMode")
        let mock = MockLibraryPersistence()

        let vm = LibraryViewModel(persistence: mock, preferenceStore: prefs)
        #expect(vm.sortOrder == .title, "Empty string should fall back to default sort order")
        #expect(vm.viewMode == .grid, "Empty string should fall back to default view mode")
    }
}
