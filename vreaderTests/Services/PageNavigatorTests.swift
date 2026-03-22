// Purpose: Tests for PageNavigator protocol and BasePageNavigator.
// Validates initial state, navigation, clamping, progression, and delegate notification.
//
// @coordinates-with PageNavigator.swift, BasePageNavigator.swift

import Testing
@testable import vreader

// MARK: - Mock Delegate

@MainActor
private final class MockPageNavigatorDelegate: PageNavigatorDelegate {
    var navigatedPages: [Int] = []

    func pageNavigator(_ navigator: any PageNavigator, didNavigateToPage page: Int) {
        navigatedPages.append(page)
    }
}

// MARK: - Tests

@Suite("BasePageNavigator")
struct PageNavigatorTests {

    // MARK: - Initial State

    @Test @MainActor func initialState_page0_totalPages0() {
        let nav = BasePageNavigator()
        #expect(nav.currentPage == 0)
        #expect(nav.totalPages == 0)
    }

    // MARK: - nextPage

    @Test @MainActor func nextPage_incrementsCurrentPage() {
        let nav = BasePageNavigator()
        nav.totalPages = 5
        nav.nextPage()
        #expect(nav.currentPage == 1)
    }

    @Test @MainActor func nextPage_atEnd_noOp() {
        let nav = BasePageNavigator()
        nav.totalPages = 3
        nav.jumpToPage(2) // last page (0-indexed)
        nav.nextPage()
        #expect(nav.currentPage == 2)
    }

    @Test @MainActor func nextPage_zeroTotalPages_noOp() {
        let nav = BasePageNavigator()
        nav.totalPages = 0
        nav.nextPage()
        #expect(nav.currentPage == 0)
    }

    // MARK: - previousPage

    @Test @MainActor func prevPage_decrementsCurrentPage() {
        let nav = BasePageNavigator()
        nav.totalPages = 5
        nav.jumpToPage(2)
        nav.previousPage()
        #expect(nav.currentPage == 1)
    }

    @Test @MainActor func prevPage_atBeginning_noOp() {
        let nav = BasePageNavigator()
        nav.totalPages = 5
        nav.previousPage()
        #expect(nav.currentPage == 0)
    }

    // MARK: - jumpToPage

    @Test @MainActor func jumpTo_validPage_navigates() {
        let nav = BasePageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(5)
        #expect(nav.currentPage == 5)
    }

    @Test @MainActor func jumpTo_negativeIndex_clampsTo0() {
        let nav = BasePageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(5)
        nav.jumpToPage(-1)
        #expect(nav.currentPage == 0)
    }

    @Test @MainActor func jumpTo_beyondEnd_clampsToLast() {
        let nav = BasePageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(100)
        #expect(nav.currentPage == 9)
    }

    @Test @MainActor func jumpTo_zeroTotalPages_clampsTo0() {
        let nav = BasePageNavigator()
        nav.totalPages = 0
        nav.jumpToPage(5)
        #expect(nav.currentPage == 0)
    }

    @Test @MainActor func jumpTo_currentPage_isNoOp() {
        let nav = BasePageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(3)
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate
        nav.jumpToPage(3) // same page — should not notify
        #expect(nav.currentPage == 3)
        #expect(delegate.navigatedPages.isEmpty)
    }

    // MARK: - totalPages (zero document)

    @Test @MainActor func totalPages_zeroDocument_returns0() {
        let nav = BasePageNavigator()
        #expect(nav.totalPages == 0)
    }

    // MARK: - progression

    @Test @MainActor func progression_computedCorrectly() {
        let nav = BasePageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(5)
        // 5 / (10 - 1) = 5/9 ≈ 0.5556
        #expect(abs(nav.progression - (5.0 / 9.0)) < 0.0001)
    }

    @Test @MainActor func progression_singlePage_returns0() {
        let nav = BasePageNavigator()
        nav.totalPages = 1
        #expect(nav.progression == 0.0)
    }

    @Test @MainActor func progression_zeroPages_returns0() {
        let nav = BasePageNavigator()
        nav.totalPages = 0
        #expect(nav.progression == 0.0)
    }

    @Test @MainActor func progression_lastPage_returns1() {
        let nav = BasePageNavigator()
        nav.totalPages = 5
        nav.jumpToPage(4) // last page (0-indexed)
        #expect(nav.progression == 1.0)
    }

    @Test @MainActor func progression_firstPage_returns0() {
        let nav = BasePageNavigator()
        nav.totalPages = 5
        #expect(nav.progression == 0.0)
    }

    // MARK: - Delegate notification

    @Test @MainActor func delegate_notifiedOnNextPage() {
        let nav = BasePageNavigator()
        nav.totalPages = 5
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate
        nav.nextPage()
        #expect(delegate.navigatedPages == [1])
    }

    @Test @MainActor func delegate_notifiedOnPreviousPage() {
        let nav = BasePageNavigator()
        nav.totalPages = 5
        nav.jumpToPage(3)
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate
        nav.previousPage()
        #expect(delegate.navigatedPages == [2])
    }

    @Test @MainActor func delegate_notifiedOnJumpToPage() {
        let nav = BasePageNavigator()
        nav.totalPages = 10
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate
        nav.jumpToPage(7)
        #expect(delegate.navigatedPages == [7])
    }

    @Test @MainActor func delegate_notNotifiedOnNoOpAtEnd() {
        let nav = BasePageNavigator()
        nav.totalPages = 3
        nav.jumpToPage(2)
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate
        nav.nextPage() // already at end — no-op
        #expect(delegate.navigatedPages.isEmpty)
    }

    @Test @MainActor func delegate_notNotifiedOnNoOpAtBeginning() {
        let nav = BasePageNavigator()
        nav.totalPages = 5
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate
        nav.previousPage() // already at 0 — no-op
        #expect(delegate.navigatedPages.isEmpty)
    }

    @Test @MainActor func delegate_multipleNavigations_allRecorded() {
        let nav = BasePageNavigator()
        nav.totalPages = 10
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate
        nav.nextPage()     // → 1
        nav.nextPage()     // → 2
        nav.jumpToPage(8)  // → 8
        nav.previousPage() // → 7
        #expect(delegate.navigatedPages == [1, 2, 8, 7])
    }

    // MARK: - totalPages changes

    @Test @MainActor func totalPages_reducedBelowCurrentPage_clampsCurrentPage() {
        let nav = BasePageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(8)
        nav.totalPages = 5  // now only 0..4 valid
        #expect(nav.currentPage <= 4)
    }

    @Test @MainActor func totalPages_reducedBelowCurrentPage_notifiesDelegate() {
        // Audit Issue 5: When totalPages shrinks and currentPage is clamped,
        // the delegate must be notified so the UI updates.
        let nav = BasePageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(8)
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate

        nav.totalPages = 5  // clamps currentPage from 8 → 4

        #expect(nav.currentPage == 4)
        #expect(delegate.navigatedPages == [4],
                "Delegate should be notified when totalPages shrink causes currentPage clamp")
    }

    @Test @MainActor func totalPages_reducedButNoClamp_doesNotNotifyDelegate() {
        // When totalPages shrinks but currentPage is still valid, no notification needed.
        let nav = BasePageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(3)
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate

        nav.totalPages = 8  // currentPage 3 is still valid

        #expect(nav.currentPage == 3)
        #expect(delegate.navigatedPages.isEmpty,
                "Delegate should NOT be notified when clamp is not triggered")
    }

    @Test @MainActor func totalPages_reducedToZero_clampsAndNotifiesDelegate() {
        // Edge: totalPages set to 0 while on page > 0.
        let nav = BasePageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(5)
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate

        nav.totalPages = 0  // clamps currentPage from 5 → 0

        #expect(nav.currentPage == 0)
        #expect(delegate.navigatedPages == [0],
                "Delegate should be notified when totalPages=0 forces clamp to page 0")
    }

    // MARK: - Weak delegate (no retain cycle)

    @Test @MainActor func delegate_isWeak_noRetainCycle() {
        let nav = BasePageNavigator()
        nav.totalPages = 5
        var delegate: MockPageNavigatorDelegate? = MockPageNavigatorDelegate()
        nav.delegate = delegate
        delegate = nil
        // Should not crash and delegate should be nil
        nav.nextPage()
        #expect(nav.currentPage == 1)
    }
}
