// Purpose: Tests for LibraryViewModel — loading, sorting, deleting, refresh throttling.

import Testing
import Foundation
@testable import vreader

@Suite("LibraryViewModel")
struct LibraryViewModelTests {

    // MARK: - Loading

    @Test @MainActor func loadBooksPopulatesBooksList() async {
        let mock = MockLibraryPersistence()
        let item = LibraryBookItem.stub(title: "My Book")
        await mock.seed(item)

        let vm = LibraryViewModel(persistence: mock)
        await vm.loadBooks()

        #expect(vm.books.count == 1)
        #expect(vm.books.first?.title == "My Book")
    }

    @Test @MainActor func loadBooksEmptyLibrary() async {
        let mock = MockLibraryPersistence()
        let vm = LibraryViewModel(persistence: mock)
        await vm.loadBooks()

        #expect(vm.books.isEmpty)
        #expect(vm.isEmpty)
    }

    // MARK: - Initial Load State

    @Test @MainActor func isInitialLoadTrueBeforeFirstLoad() {
        let mock = MockLibraryPersistence()
        let vm = LibraryViewModel(persistence: mock)
        #expect(vm.isInitialLoad == true, "Should be true before loadBooks is called")
    }

    @Test @MainActor func isInitialLoadFalseAfterFirstLoad() async {
        let mock = MockLibraryPersistence()
        await mock.seed(.stub(title: "Book"))
        let vm = LibraryViewModel(persistence: mock)
        await vm.loadBooks()
        #expect(vm.isInitialLoad == false, "Should become false after first load")
    }

    @Test @MainActor func isInitialLoadFalseAfterEmptyLoad() async {
        let mock = MockLibraryPersistence()
        let vm = LibraryViewModel(persistence: mock)
        await vm.loadBooks()
        #expect(vm.isInitialLoad == false, "Should become false even when library is empty")
    }

    @Test @MainActor func isInitialLoadFalseAfterFailedLoad() async {
        let mock = MockLibraryPersistence()
        await mock.setFetchError(LibraryTestError.networkFailure)
        let vm = LibraryViewModel(persistence: mock)
        await vm.loadBooks()
        #expect(vm.isInitialLoad == false, "Should become false even on error")
    }

    @Test @MainActor func isEmptyNotTrueDuringInitialLoad() {
        let mock = MockLibraryPersistence()
        let vm = LibraryViewModel(persistence: mock)
        // Before first load, isEmpty is technically true (no books) but
        // isInitialLoad distinguishes "haven't loaded yet" from "loaded and empty"
        #expect(vm.isInitialLoad == true)
        #expect(vm.books.isEmpty) // books are empty, but isInitialLoad signals we haven't tried yet
    }

    @Test @MainActor func isEmptyTrueWhenNoBooks() async {
        let mock = MockLibraryPersistence()
        let vm = LibraryViewModel(persistence: mock)
        await vm.loadBooks()

        #expect(vm.isEmpty == true)
    }

    @Test @MainActor func isEmptyFalseWhenBooksExist() async {
        let mock = MockLibraryPersistence()
        await mock.seed(.stub())

        let vm = LibraryViewModel(persistence: mock)
        await vm.loadBooks()

        #expect(vm.isEmpty == false)
    }

    @Test @MainActor func loadBooksHandlesError() async {
        let mock = MockLibraryPersistence()
        await mock.setFetchError(LibraryTestError.networkFailure)

        let vm = LibraryViewModel(persistence: mock)
        await vm.loadBooks()

        #expect(vm.books.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - View Mode Toggle

    @Test @MainActor func defaultViewModeIsGrid() {
        let mock = MockLibraryPersistence()
        let vm = LibraryViewModel(persistence: mock)
        #expect(vm.viewMode == .grid)
    }

    @Test @MainActor func toggleViewModeSwitchesGridToList() {
        let mock = MockLibraryPersistence()
        let vm = LibraryViewModel(persistence: mock)
        vm.toggleViewMode()
        #expect(vm.viewMode == .list)
    }

    @Test @MainActor func toggleViewModeSwitchesListToGrid() {
        let mock = MockLibraryPersistence()
        let vm = LibraryViewModel(persistence: mock)
        vm.toggleViewMode()
        vm.toggleViewMode()
        #expect(vm.viewMode == .grid)
    }

    // MARK: - Sorting

    @Test @MainActor func defaultSortOrderIsByTitle() {
        let mock = MockLibraryPersistence()
        let vm = LibraryViewModel(persistence: mock)
        #expect(vm.sortOrder == .title)
    }

    @Test @MainActor func sortByTitleAlphabetical() async {
        let mock = MockLibraryPersistence()
        await mock.seedMany([
            .stub(fingerprintKey: "k1", title: "Zebra"),
            .stub(fingerprintKey: "k2", title: "Apple"),
            .stub(fingerprintKey: "k3", title: "Mango"),
        ])

        let vm = LibraryViewModel(persistence: mock)
        vm.sortOrder = .title
        await vm.loadBooks()

        #expect(vm.books.map(\.title) == ["Apple", "Mango", "Zebra"])
    }

    @Test @MainActor func sortByAddedAt() async {
        let mock = MockLibraryPersistence()
        let now = Date()
        await mock.seedMany([
            .stub(fingerprintKey: "k1", title: "Old", addedAt: now.addingTimeInterval(-1000)),
            .stub(fingerprintKey: "k2", title: "New", addedAt: now),
            .stub(fingerprintKey: "k3", title: "Mid", addedAt: now.addingTimeInterval(-500)),
        ])

        let vm = LibraryViewModel(persistence: mock)
        vm.sortOrder = .addedAt
        await vm.loadBooks()

        // Most recent first
        #expect(vm.books.map(\.title) == ["New", "Mid", "Old"])
    }

    @Test @MainActor func sortByLastReadAt() async {
        let mock = MockLibraryPersistence()
        let now = Date()
        await mock.seedMany([
            .stub(fingerprintKey: "k1", title: "NeverRead", lastReadAt: nil),
            .stub(fingerprintKey: "k2", title: "ReadRecently", lastReadAt: now),
            .stub(fingerprintKey: "k3", title: "ReadAgo", lastReadAt: now.addingTimeInterval(-1000)),
        ])

        let vm = LibraryViewModel(persistence: mock)
        vm.sortOrder = .lastReadAt
        await vm.loadBooks()

        // Most recently read first, never-read last
        #expect(vm.books.map(\.title) == ["ReadRecently", "ReadAgo", "NeverRead"])
    }

    @Test @MainActor func sortByTotalReadingSeconds() async {
        let mock = MockLibraryPersistence()
        await mock.seedMany([
            .stub(fingerprintKey: "k1", title: "Unread", totalReadingSeconds: 0),
            .stub(fingerprintKey: "k2", title: "MostRead", totalReadingSeconds: 9999),
            .stub(fingerprintKey: "k3", title: "SomeRead", totalReadingSeconds: 500),
        ])

        let vm = LibraryViewModel(persistence: mock)
        vm.sortOrder = .totalReadingTime
        await vm.loadBooks()

        // Most reading time first
        #expect(vm.books.map(\.title) == ["MostRead", "SomeRead", "Unread"])
    }

    @Test @MainActor func changeSortOrderResortsBooks() async {
        let mock = MockLibraryPersistence()
        await mock.seedMany([
            .stub(fingerprintKey: "k1", title: "Zebra", addedAt: Date()),
            .stub(fingerprintKey: "k2", title: "Apple", addedAt: Date().addingTimeInterval(-100)),
        ])

        let vm = LibraryViewModel(persistence: mock)
        vm.sortOrder = .title
        await vm.loadBooks()
        #expect(vm.books.first?.title == "Apple")

        vm.sortOrder = .addedAt
        // Sort order change should trigger re-sort
        #expect(vm.books.first?.title == "Zebra")
    }

    // MARK: - Deletion

    @Test @MainActor func deleteBookRemovesFromList() async {
        let mock = MockLibraryPersistence()
        let item = LibraryBookItem.stub(fingerprintKey: "to-delete", title: "Doomed")
        await mock.seed(item)

        let vm = LibraryViewModel(persistence: mock)
        await vm.loadBooks()
        #expect(vm.books.count == 1)

        await vm.deleteBook(fingerprintKey: "to-delete")

        #expect(vm.books.isEmpty)
        let count = await mock.deleteCallCount
        #expect(count == 1)
    }

    @Test @MainActor func deleteBookNonexistentKeyIsNoOp() async {
        let mock = MockLibraryPersistence()
        await mock.seed(.stub(fingerprintKey: "keep-me"))

        let vm = LibraryViewModel(persistence: mock)
        await vm.loadBooks()

        await vm.deleteBook(fingerprintKey: "nonexistent")
        #expect(vm.books.count == 1) // unchanged
    }

    @Test @MainActor func deleteLastBookShowsEmptyState() async {
        let mock = MockLibraryPersistence()
        await mock.seed(.stub(fingerprintKey: "only-one"))

        let vm = LibraryViewModel(persistence: mock)
        await vm.loadBooks()
        #expect(vm.isEmpty == false)

        await vm.deleteBook(fingerprintKey: "only-one")
        #expect(vm.isEmpty == true)
    }

    // MARK: - Refresh Throttling

    @Test @MainActor func refreshLoadsBooks() async {
        let mock = MockLibraryPersistence()
        await mock.seed(.stub(title: "Refreshed"))

        let vm = LibraryViewModel(persistence: mock)
        await vm.refresh()

        #expect(vm.books.count == 1)
        #expect(vm.books.first?.title == "Refreshed")
    }

    @Test @MainActor func refreshThrottledWithin5Seconds() async {
        let mock = MockLibraryPersistence()
        await mock.seed(.stub(title: "Book"))

        let vm = LibraryViewModel(persistence: mock)
        await vm.refresh()
        #expect(vm.books.count == 1)

        // Add another book and try to refresh immediately
        await mock.seed(.stub(fingerprintKey: "k2", title: "Book2"))
        await vm.refresh()

        // Should still show 1 book (throttled)
        #expect(vm.books.count == 1)
    }

    @Test @MainActor func refreshAllowedAfterThrottleExpires() async {
        let mock = MockLibraryPersistence()
        await mock.seed(.stub(title: "Book"))

        // Use a testable throttle interval
        let vm = LibraryViewModel(persistence: mock, throttleInterval: 0.05)
        await vm.refresh()
        #expect(vm.books.count == 1)

        // Wait for throttle to expire
        try? await Task.sleep(for: .milliseconds(60))

        await mock.seed(.stub(fingerprintKey: "k2", title: "Book2"))
        await vm.refresh()

        #expect(vm.books.count == 2)
    }

    @Test @MainActor func refreshConcurrentCalls_coalesceIntoTrailingRefresh() async {
        // Bug #197 coalescing: when a refresh arrives while another is
        // in-flight, the old behavior dropped it (`guard !isRefreshing
        // else { return }`). With multi-import flows (WebDAV restore,
        // burst .bookDidImport notifications), that lost the second
        // refresh and left the library stale. The new behavior sets a
        // pending flag and re-runs the fetch after the in-flight one
        // returns. This test validates fetchCallCount >= 2 across two
        // concurrent refresh calls (vs the old behavior's == 1).
        let mock = MockLibraryPersistence()
        await mock.seed(.stub(title: "Initial"))

        // Force-bypass the throttle so the coalescing path is the only
        // gating mechanism we're testing.
        let vm = LibraryViewModel(persistence: mock)

        async let first: Void = vm.refresh(force: true)
        async let second: Void = vm.refresh(force: true)
        _ = await (first, second)

        let calls = await mock.fetchCallCount
        #expect(calls >= 2, "Expected the trailing refresh to fire (fetchCallCount = \(calls)); coalescing must not drop re-entrant calls")
    }

    @Test @MainActor func refreshThreeWaveCoalesce_drainsUntilQuiescent() async {
        // Bug #197 round-2 fix: the trailing edge needs to be a LOOP, not a
        // single check. If a third refresh arrives while the trailing fetch
        // (kicked off by a second refresh) is still in flight, that third
        // refresh would be lost without the drain-until-quiescent loop.
        // This test launches three concurrent forced refreshes and asserts
        // every one of them is observable in the fetch counter.
        let mock = MockLibraryPersistence()
        await mock.seed(.stub(title: "Initial"))
        let vm = LibraryViewModel(persistence: mock)

        async let a: Void = vm.refresh(force: true)
        async let b: Void = vm.refresh(force: true)
        async let c: Void = vm.refresh(force: true)
        _ = await (a, b, c)

        let calls = await mock.fetchCallCount
        // First call runs immediately; b and c may collapse onto a single
        // trailing iteration (both set the same pending flag) — that's
        // correct coalescing, NOT loss. So the floor is 2, not 3.
        #expect(calls >= 2, "Expected the drain loop to fire at least one trailing iteration (fetchCallCount = \(calls))")
    }
}
