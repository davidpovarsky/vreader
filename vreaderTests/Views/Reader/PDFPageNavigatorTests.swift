// Purpose: Tests for PDFPageNavigator — validates PDF page navigation
// via BasePageNavigator with sync method for PDFView page changes.
//
// Pure unit tests — no PDFKit or PDFView dependency.
//
// @coordinates-with PDFPageNavigator.swift, BasePageNavigator.swift

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

@Suite("PDFPageNavigator")
struct PDFPageNavigatorTests {

    // MARK: - Initial State

    @Test @MainActor func initialPage_isCurrentPDFPage() {
        // Navigator should start at page 0 by default
        let nav = PDFPageNavigator()
        #expect(nav.currentPage == 0)
    }

    // MARK: - nextPage

    @Test @MainActor func nextPage_navigatesToNextPDFPage() {
        let nav = PDFPageNavigator()
        nav.totalPages = 10
        nav.nextPage()
        #expect(nav.currentPage == 1)
    }

    @Test @MainActor func nextPage_atLastPage_noOp() {
        let nav = PDFPageNavigator()
        nav.totalPages = 5
        nav.jumpToPage(4) // last page (0-indexed)
        nav.nextPage()
        #expect(nav.currentPage == 4)
    }

    @Test @MainActor func nextPage_zeroPages_noOp() {
        let nav = PDFPageNavigator()
        nav.totalPages = 0
        nav.nextPage()
        #expect(nav.currentPage == 0)
    }

    // MARK: - previousPage

    @Test @MainActor func prevPage_navigatesToPrevPDFPage() {
        let nav = PDFPageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(5)
        nav.previousPage()
        #expect(nav.currentPage == 4)
    }

    @Test @MainActor func prevPage_atFirstPage_noOp() {
        let nav = PDFPageNavigator()
        nav.totalPages = 10
        nav.previousPage()
        #expect(nav.currentPage == 0)
    }

    // MARK: - jumpToPage

    @Test @MainActor func jumpToPage_validIndex_navigates() {
        let nav = PDFPageNavigator()
        nav.totalPages = 20
        nav.jumpToPage(5)
        #expect(nav.currentPage == 5)
    }

    @Test @MainActor func jumpToPage_beyondEnd_clampsToLast() {
        let nav = PDFPageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(100)
        #expect(nav.currentPage == 9)
    }

    @Test @MainActor func jumpToPage_negative_clampsToZero() {
        let nav = PDFPageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(5)
        nav.jumpToPage(-1)
        #expect(nav.currentPage == 0)
    }

    // MARK: - totalPages

    @Test @MainActor func totalPages_matchesPDFPageCount() {
        let nav = PDFPageNavigator()
        nav.totalPages = 42
        #expect(nav.totalPages == 42)
    }

    // MARK: - progression

    @Test @MainActor func progression_matchesPDFPosition() {
        // page 5 of 10 → 5 / (10 - 1) = 5/9 ≈ 0.5556
        let nav = PDFPageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(5)
        let expected = 5.0 / 9.0
        #expect(abs(nav.progression - expected) < 0.001)
    }

    @Test @MainActor func progression_firstPage_isZero() {
        let nav = PDFPageNavigator()
        nav.totalPages = 10
        #expect(nav.progression == 0.0)
    }

    @Test @MainActor func progression_lastPage_isOne() {
        let nav = PDFPageNavigator()
        nav.totalPages = 10
        nav.jumpToPage(9)
        #expect(nav.progression == 1.0)
    }

    @Test @MainActor func progression_singlePage_isZero() {
        let nav = PDFPageNavigator()
        nav.totalPages = 1
        #expect(nav.progression == 0.0)
    }

    @Test @MainActor func progression_zeroPages_isZero() {
        let nav = PDFPageNavigator()
        nav.totalPages = 0
        #expect(nav.progression == 0.0)
    }

    // MARK: - syncFromPDFView

    @Test @MainActor func syncFromPDFView_updatesCurrentPage() {
        // Simulates what happens when PDFViewPageChanged notification fires
        let nav = PDFPageNavigator()
        nav.totalPages = 10
        nav.syncCurrentPage(3)
        #expect(nav.currentPage == 3)
    }

    @Test @MainActor func syncFromPDFView_clampsOutOfRange() {
        let nav = PDFPageNavigator()
        nav.totalPages = 5
        nav.syncCurrentPage(100)
        #expect(nav.currentPage == 4) // clamped to last page
    }

    @Test @MainActor func syncFromPDFView_samePageIsNoOp() {
        let nav = PDFPageNavigator()
        nav.totalPages = 10
        nav.syncCurrentPage(3)
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate
        nav.syncCurrentPage(3) // same page — should not notify
        #expect(delegate.navigatedPages.isEmpty)
    }

    @Test @MainActor func syncFromPDFView_notifiesDelegate() {
        let nav = PDFPageNavigator()
        nav.totalPages = 10
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate
        nav.syncCurrentPage(7)
        #expect(delegate.navigatedPages == [7])
    }

    // MARK: - Delegate notification (inherited from BasePageNavigator)

    @Test @MainActor func delegate_notifiedOnNext() {
        let nav = PDFPageNavigator()
        nav.totalPages = 5
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate
        nav.nextPage()
        #expect(delegate.navigatedPages == [1])
    }

    @Test @MainActor func delegate_notNotifiedOnNoOp() {
        let nav = PDFPageNavigator()
        nav.totalPages = 5
        nav.jumpToPage(4)
        let delegate = MockPageNavigatorDelegate()
        nav.delegate = delegate
        nav.nextPage() // at end — no-op
        #expect(delegate.navigatedPages.isEmpty)
    }

    // MARK: - Edge cases

    @Test @MainActor func singlePagePDF_nextAndPrevAreNoOps() {
        let nav = PDFPageNavigator()
        nav.totalPages = 1
        nav.nextPage()
        #expect(nav.currentPage == 0)
        nav.previousPage()
        #expect(nav.currentPage == 0)
    }

    @Test @MainActor func rapidRepeatedNext_advancesCorrectly() {
        let nav = PDFPageNavigator()
        nav.totalPages = 100
        for _ in 0..<50 {
            nav.nextPage()
        }
        #expect(nav.currentPage == 50)
    }

    @Test @MainActor func rapidRepeatedPrev_retreatsCorrectly() {
        let nav = PDFPageNavigator()
        nav.totalPages = 100
        nav.jumpToPage(50)
        for _ in 0..<50 {
            nav.previousPage()
        }
        #expect(nav.currentPage == 0)
    }

    @Test @MainActor func rapidRepeatedPrev_beyondZero_staysAtZero() {
        let nav = PDFPageNavigator()
        nav.totalPages = 5
        for _ in 0..<10 {
            nav.previousPage()
        }
        #expect(nav.currentPage == 0)
    }

    @Test @MainActor func rapidRepeatedNext_beyondEnd_staysAtEnd() {
        let nav = PDFPageNavigator()
        nav.totalPages = 5
        for _ in 0..<10 {
            nav.nextPage()
        }
        #expect(nav.currentPage == 4)
    }
}
