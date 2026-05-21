// Purpose: Tests for AutoPageTurner — timer-based auto page advancement.
// Validates state transitions, interval clamping, last-page stop, and timer lifecycle.
//
// @coordinates-with AutoPageTurner.swift, PageNavigator.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Mock Navigator

@MainActor
private final class MockNavigator: PageNavigator {
    var currentPage: Int = 0
    var totalPages: Int = 10
    weak var delegate: (any PageNavigatorDelegate)?
    var nextPageCallCount = 0

    var progression: Double {
        guard totalPages > 1 else { return 0.0 }
        return Double(currentPage) / Double(totalPages - 1)
    }

    func nextPage() {
        let maxPage = max(totalPages - 1, 0)
        guard currentPage < maxPage else { return }
        currentPage += 1
        nextPageCallCount += 1
        // Mirror BasePageNavigator: fire the delegate on a real page change so
        // tests can assert the navigator broadcasts page advances the same way
        // the production navigator does.
        delegate?.pageNavigator(self, didNavigateToPage: currentPage)
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
    }

    func jumpToPage(_ page: Int) {
        let maxPage = max(totalPages - 1, 0)
        currentPage = max(0, min(page, maxPage))
    }
}

// MARK: - Tests

@Suite("AutoPageTurner")
struct AutoPageTurnerTests {

    // MARK: - Default State

    @Test @MainActor func defaultState_isIdle() {
        let turner = AutoPageTurner()
        #expect(turner.state == .idle)
    }

    @Test @MainActor func defaultInterval_5seconds() {
        let turner = AutoPageTurner()
        #expect(turner.interval == 5.0)
    }

    // MARK: - Interval Clamping

    @Test @MainActor func intervalClamped_belowMin_becomesMin() {
        let turner = AutoPageTurner()
        turner.interval = 0.5
        #expect(turner.interval == 1.0)
    }

    @Test @MainActor func intervalClamped_aboveMax_becomesMax() {
        let turner = AutoPageTurner()
        turner.interval = 100.0
        #expect(turner.interval == 60.0)
    }

    @Test @MainActor func intervalClamped_exactMin_stays() {
        let turner = AutoPageTurner()
        turner.interval = 1.0
        #expect(turner.interval == 1.0)
    }

    @Test @MainActor func intervalClamped_exactMax_stays() {
        let turner = AutoPageTurner()
        turner.interval = 60.0
        #expect(turner.interval == 60.0)
    }

    @Test @MainActor func intervalClamped_negativeValue_becomesMin() {
        let turner = AutoPageTurner()
        turner.interval = -5.0
        #expect(turner.interval == 1.0)
    }

    @Test @MainActor func intervalClamped_zero_becomesMin() {
        let turner = AutoPageTurner()
        turner.interval = 0.0
        #expect(turner.interval == 1.0)
    }

    /// Bug #191 Codex audit Medium: NaN propagates through
    /// `max(1.0, min(60.0, .nan))` because NaN comparisons return false.
    /// Without the `isFinite` guard, `Task.sleep(for: .seconds(.nan))` in
    /// `scheduleTimer` would hit undefined behavior. Non-finite inputs
    /// reset to the 5s default.
    @Test @MainActor func intervalClamped_nan_resetsToDefault() {
        let turner = AutoPageTurner()
        turner.interval = .nan
        #expect(turner.interval == 5.0)
    }

    @Test @MainActor func intervalClamped_positiveInfinity_resetsToDefault() {
        let turner = AutoPageTurner()
        turner.interval = .infinity
        #expect(turner.interval == 5.0)
    }

    @Test @MainActor func intervalClamped_negativeInfinity_resetsToDefault() {
        let turner = AutoPageTurner()
        turner.interval = -.infinity
        #expect(turner.interval == 5.0)
    }

    /// Bug #191 (GH #682) regression: setting `interval` repeatedly must
    /// not recurse. Pre-fix, the original `var interval = 5.0 { didSet {
    /// interval = clamp(interval) } }` under `@Observable` caused
    /// `_interval.setter ↔ _interval.didset ↔ interval.setter` recursion
    /// that hit the stack-guard fault at ~23k frames. This test asserts
    /// repeated writes terminate normally — if the recursion regresses,
    /// the test process aborts before the `#expect` line.
    @Test @MainActor func intervalAssignment_doesNotRecurse_bug191() {
        let turner = AutoPageTurner()
        // Each assignment exercises the @Observable wrapper-vs-storage path
        // that triggered the original recursion. Cover in-range, below-min,
        // above-max, and a back-to-back-same-value pair so any didSet
        // re-entrance would manifest as the test killing itself.
        turner.interval = 3.0
        turner.interval = 0.5
        turner.interval = 100.0
        turner.interval = 30.0
        turner.interval = 30.0
        #expect(turner.interval == 30.0,
                "expected final clamped value 30.0; reaching this assertion is itself the load-bearing signal that no recursion occurred")
    }

    // MARK: - State Transitions

    @Test @MainActor func start_transitionsToRunning() {
        let turner = AutoPageTurner()
        let nav = MockNavigator()
        turner.start(navigator: nav)
        #expect(turner.state == .running)
        turner.stop()
    }

    @Test @MainActor func pause_transitionsToPaused() {
        let turner = AutoPageTurner()
        let nav = MockNavigator()
        turner.start(navigator: nav)
        turner.pause()
        #expect(turner.state == .paused)
        turner.stop()
    }

    @Test @MainActor func resume_transitionsToRunning() {
        let turner = AutoPageTurner()
        let nav = MockNavigator()
        turner.start(navigator: nav)
        turner.pause()
        turner.resume()
        #expect(turner.state == .running)
        turner.stop()
    }

    @Test @MainActor func stop_transitionsToIdle() {
        let turner = AutoPageTurner()
        let nav = MockNavigator()
        turner.start(navigator: nav)
        turner.stop()
        #expect(turner.state == .idle)
    }

    @Test @MainActor func pause_whileIdle_noOp() {
        let turner = AutoPageTurner()
        turner.pause()
        #expect(turner.state == .idle)
    }

    @Test @MainActor func resume_whileIdle_noOp() {
        let turner = AutoPageTurner()
        turner.resume()
        #expect(turner.state == .idle)
    }

    @Test @MainActor func stop_whileIdle_noOp() {
        let turner = AutoPageTurner()
        turner.stop()
        #expect(turner.state == .idle)
    }

    @Test @MainActor func start_whileAlreadyRunning_resetsTimer() {
        let turner = AutoPageTurner()
        let nav = MockNavigator()
        turner.start(navigator: nav)
        turner.start(navigator: nav) // second start
        #expect(turner.state == .running)
        turner.stop()
    }

    // MARK: - Timer Behavior

    @Test @MainActor func start_callsNextPage_afterInterval() async throws {
        let turner = AutoPageTurner()
        turner.interval = 1.0 // minimum for fast test
        let nav = MockNavigator()
        nav.totalPages = 10
        nav.currentPage = 0

        turner.start(navigator: nav)
        // Wait slightly longer than interval for the timer to fire
        try await Task.sleep(for: .milliseconds(1200))

        #expect(nav.nextPageCallCount >= 1)
        turner.stop()
    }

    @Test @MainActor func stop_cancelsTimer_noPagesAfterStop() async throws {
        let turner = AutoPageTurner()
        turner.interval = 1.0
        let nav = MockNavigator()
        nav.totalPages = 10

        turner.start(navigator: nav)
        turner.stop()

        let callsBefore = nav.nextPageCallCount
        try await Task.sleep(for: .milliseconds(1500))

        #expect(nav.nextPageCallCount == callsBefore)
    }

    @Test @MainActor func pause_suspendsTimer_noPagesWhilePaused() async throws {
        let turner = AutoPageTurner()
        turner.interval = 1.0
        let nav = MockNavigator()
        nav.totalPages = 10

        turner.start(navigator: nav)
        turner.pause()

        let callsBefore = nav.nextPageCallCount
        try await Task.sleep(for: .milliseconds(1500))

        #expect(nav.nextPageCallCount == callsBefore)
        turner.stop()
    }

    @Test @MainActor func stopsAtLastPage() async throws {
        let turner = AutoPageTurner()
        turner.interval = 1.0
        let nav = MockNavigator()
        nav.totalPages = 3
        nav.currentPage = 2 // already at last page

        turner.start(navigator: nav)
        try await Task.sleep(for: .milliseconds(1200))

        #expect(nav.nextPageCallCount == 0)
        #expect(turner.state == .idle, "Should auto-stop at last page")
    }

    // MARK: - View-Sync Bridge (Bug #258 / GH #1125)

    /// Bug #258 (GH #1125): the timer's `nextPage()` advances the navigator's
    /// internal page, but the MD/TXT paged view renders from the explicit
    /// `currentPage: uiState.pagedCurrentPage` param — synced from
    /// `nav.currentPage` ONLY in `TextReaderUIState.syncPagedState()`, which
    /// was called ONLY from the `.readerNextPage` observer that the auto-turn
    /// timer bypasses. So the page never re-rendered and `snapshot.position`
    /// stayed flat. The `AutoPageTurnerTests` MockNavigator approach is exactly
    /// why criterion 4 passed while criterion 5 failed: the suite proved the
    /// timer FIRES `nextPage()`, but nothing tested that a timer-driven advance
    /// drives the container's observable view-sync.
    ///
    /// The fix: `AutoPageTurner` invokes an `onAdvance` callback after each
    /// timer-driven `nextPage()`. The container installs it to run the same
    /// `syncPagedState()` + position update the `.readerNextPage` observer
    /// does — WITHOUT the observer's `pause()` (posting `.readerNextPage` from
    /// the timer would immediately pause the turner, halting auto-advance after
    /// one tick). This test drives a timer-tick and asserts the bridge fires.
    @Test @MainActor func timerAdvance_invokesOnAdvanceCallback() async throws {
        let turner = AutoPageTurner()
        turner.interval = 1.0
        let nav = MockNavigator()
        nav.totalPages = 10
        nav.currentPage = 0

        nonisolated(unsafe) var onAdvanceCount = 0
        nonisolated(unsafe) var observedPageAtAdvance: Int?
        turner.onAdvance = {
            onAdvanceCount += 1
            observedPageAtAdvance = nav.currentPage
        }

        turner.start(navigator: nav)
        try await Task.sleep(for: .milliseconds(1200))
        turner.stop()

        #expect(onAdvanceCount >= 1,
                "onAdvance must fire on each timer-driven page turn so the container can re-sync pagedCurrentPage + position")
        // The callback must fire AFTER nextPage() so the container observes the
        // already-advanced page (otherwise syncPagedState reads the stale page).
        #expect(observedPageAtAdvance == nav.currentPage,
                "onAdvance must run after nextPage() advances the navigator")
        #expect(nav.currentPage >= 1, "navigator must have advanced")
    }

    /// The `onAdvance` callback must NOT fire when the timer hits the last page
    /// (no actual advance happened — `scheduleTimer` stops before `nextPage()`).
    /// A spurious callback there would re-sync / re-persist position with no
    /// page change, and worse could mask the auto-stop.
    @Test @MainActor func timerAtLastPage_doesNotInvokeOnAdvance() async throws {
        let turner = AutoPageTurner()
        turner.interval = 1.0
        let nav = MockNavigator()
        nav.totalPages = 3
        nav.currentPage = 2 // already at last page

        nonisolated(unsafe) var onAdvanceCount = 0
        turner.onAdvance = { onAdvanceCount += 1 }

        turner.start(navigator: nav)
        try await Task.sleep(for: .milliseconds(1200))

        #expect(onAdvanceCount == 0, "onAdvance must not fire when no page advance occurs")
        #expect(turner.state == .idle, "Should auto-stop at last page")
    }

    /// `stop()` must clear the `onAdvance` callback's effect — after stop, no
    /// further timer ticks fire it. Guards against a stale closure surviving a
    /// reader teardown and re-syncing a deallocated container.
    @Test @MainActor func stop_preventsFurtherOnAdvance() async throws {
        let turner = AutoPageTurner()
        turner.interval = 1.0
        let nav = MockNavigator()
        nav.totalPages = 10

        nonisolated(unsafe) var onAdvanceCount = 0
        turner.onAdvance = { onAdvanceCount += 1 }

        turner.start(navigator: nav)
        turner.stop()
        let countAtStop = onAdvanceCount
        try await Task.sleep(for: .milliseconds(1500))

        #expect(onAdvanceCount == countAtStop, "no onAdvance after stop")
    }
}
