// Purpose: Integration tests for wiring NativeTextPaginator, AutoPageTurner,
// and PageTurnAnimator into TXT/MD containers.
// Validates that paged mode produces correct page counts, navigation works,
// auto page turning wires correctly, and animation setting persists.
//
// @coordinates-with: NativeTextPaginator.swift, AutoPageTurner.swift,
//   PageTurnAnimator.swift, ReaderSettingsStore.swift, NativeTextPagedView.swift

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

// MARK: - ReaderSettingsStore pageTurnAnimation Tests

@Suite("ReaderSettingsStore - pageTurnAnimation")
@MainActor
struct ReaderSettingsStore_PageTurnAnimationTests {
    private func makeStore() -> ReaderSettingsStore {
        ReaderSettingsStore(defaults: UserDefaults(suiteName: "RSS-PTA-\(UUID().uuidString)")!)
    }

    @Test func defaultPageTurnAnimation_isNone() {
        let store = makeStore()
        #expect(store.pageTurnAnimation == .none)
    }

    @Test func pageTurnAnimation_persistsToDefaults() {
        let suiteName = "RSS-PTA-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        var store1 = ReaderSettingsStore(defaults: defaults)
        store1.pageTurnAnimation = .slide

        let store2 = ReaderSettingsStore(defaults: defaults)
        #expect(store2.pageTurnAnimation == .slide)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func pageTurnAnimation_invalidRawValue_fallsBackToNone() {
        let suiteName = "RSS-PTA-invalid-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("fancy", forKey: ReaderSettingsStore.pageTurnAnimationKey)

        let store = ReaderSettingsStore(defaults: defaults)
        #expect(store.pageTurnAnimation == .none)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func pageTurnAnimation_allValues_roundTrip() {
        let suiteName = "RSS-PTA-all-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        for animation in PageTurnAnimation.allCases {
            var store = ReaderSettingsStore(defaults: defaults)
            store.pageTurnAnimation = animation

            let reloaded = ReaderSettingsStore(defaults: defaults)
            #expect(reloaded.pageTurnAnimation == animation,
                    "\(animation.rawValue) should persist and reload")
        }

        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - NativeTextPageNavigator Tests

#if canImport(UIKit)

@Suite("NativeTextPageNavigator")
@MainActor
struct NativeTextPageNavigatorTests {

    private let defaultFont = UIFont.systemFont(ofSize: 17)
    private let phoneViewport = CGSize(width: 375, height: 667)

    // MARK: - Basic Paging

    @Test func singlePageText_totalPagesIs1() {
        let nav = NativeTextPageNavigator()
        nav.paginate(text: "Hello", font: defaultFont, viewportSize: phoneViewport)
        #expect(nav.totalPages == 1)
        #expect(nav.currentPage == 0)
    }

    @Test func multiPageText_navigatesForwardAndBackward() {
        let nav = NativeTextPageNavigator()
        let longText = (0..<500).map { _ in "This is a line of text for pagination testing." }.joined(separator: "\n")
        nav.paginate(text: longText, font: defaultFont, viewportSize: phoneViewport)

        #expect(nav.totalPages > 1)
        #expect(nav.currentPage == 0)

        nav.nextPage()
        #expect(nav.currentPage == 1)

        nav.previousPage()
        #expect(nav.currentPage == 0)
    }

    @Test func nextPage_atLastPage_isNoOp() {
        let nav = NativeTextPageNavigator()
        nav.paginate(text: "Short", font: defaultFont, viewportSize: phoneViewport)
        // Only 1 page, so next should be no-op
        nav.nextPage()
        #expect(nav.currentPage == 0)
    }

    @Test func previousPage_atFirstPage_isNoOp() {
        let nav = NativeTextPageNavigator()
        nav.paginate(text: "Short", font: defaultFont, viewportSize: phoneViewport)
        nav.previousPage()
        #expect(nav.currentPage == 0)
    }

    @Test func jumpToPage_clampsToValidRange() {
        let nav = NativeTextPageNavigator()
        let longText = (0..<500).map { _ in "This is a line of text." }.joined(separator: "\n")
        nav.paginate(text: longText, font: defaultFont, viewportSize: phoneViewport)

        nav.jumpToPage(-5)
        #expect(nav.currentPage == 0)

        nav.jumpToPage(99999)
        #expect(nav.currentPage == nav.totalPages - 1)
    }

    @Test func emptyText_totalPagesIs0() {
        let nav = NativeTextPageNavigator()
        nav.paginate(text: "", font: defaultFont, viewportSize: phoneViewport)
        #expect(nav.totalPages == 0)
        #expect(nav.currentPage == 0)
    }

    @Test func progression_reflectsCurrentPage() {
        let nav = NativeTextPageNavigator()
        let longText = (0..<500).map { _ in "This is a line." }.joined(separator: "\n")
        nav.paginate(text: longText, font: defaultFont, viewportSize: phoneViewport)

        #expect(nav.progression == 0.0)

        if nav.totalPages > 1 {
            nav.jumpToPage(nav.totalPages - 1)
            #expect(abs(nav.progression - 1.0) < 0.01)
        }
    }

    // MARK: - Attributed String Pagination

    @Test func paginateAttributed_works() {
        let nav = NativeTextPageNavigator()
        let longText = (0..<500).map { _ in "This is a line of attributed text for pagination." }.joined(separator: "\n")
        let attrText = NSAttributedString(
            string: longText,
            attributes: [.font: defaultFont]
        )
        nav.paginateAttributed(attributedText: attrText, viewportSize: phoneViewport)
        #expect(nav.totalPages > 1)
    }

    // MARK: - Re-pagination preserves position

    @Test func repaginate_preservesApproximatePosition() {
        let nav = NativeTextPageNavigator()
        let longText = (0..<500).map { _ in "This is a line." }.joined(separator: "\n")
        nav.paginate(text: longText, font: defaultFont, viewportSize: phoneViewport)

        let totalBefore = nav.totalPages
        guard totalBefore > 2 else { return }

        // Go to middle
        let midPage = totalBefore / 2
        nav.jumpToPage(midPage)

        // Re-paginate with different font
        nav.paginate(text: longText, font: UIFont.systemFont(ofSize: 24), viewportSize: phoneViewport)

        // Position should be approximately preserved (within 30% of new total)
        let expectedApprox = Double(midPage) / Double(totalBefore - 1)
        let actualApprox = nav.progression
        #expect(abs(expectedApprox - actualApprox) < 0.3,
                "Position should be approximately preserved after repagination")
    }

    // MARK: - Delegate notifications

    @Test func delegate_calledOnPageChange() {
        let nav = NativeTextPageNavigator()
        let longText = (0..<500).map { _ in "This is a line." }.joined(separator: "\n")
        nav.paginate(text: longText, font: defaultFont, viewportSize: phoneViewport)

        let spy = PageNavDelegateSpy()
        nav.delegate = spy

        nav.nextPage()
        #expect(spy.navigatedPages.count == 1)
        #expect(spy.navigatedPages.first == 1)
    }

    // MARK: - currentPageText

    @Test func currentPageText_returnsCorrectSubstring() {
        let nav = NativeTextPageNavigator()
        let text = "Hello, world!"
        nav.paginate(text: text, font: defaultFont, viewportSize: phoneViewport)

        let pageText = nav.currentPageText(from: text)
        #expect(pageText == text, "Single-page text should return the full text")
    }

    @Test func currentPageAttributedText_returnsSubstring() {
        let nav = NativeTextPageNavigator()
        let text = "Hello"
        let attrText = NSAttributedString(string: text, attributes: [.font: defaultFont])
        nav.paginateAttributed(attributedText: attrText, viewportSize: phoneViewport)

        let result = nav.currentPageAttributedText(from: attrText)
        #expect(result?.string == text)
    }

    // MARK: - Char offset for position restore

    @Test func pageContainingOffset_works() {
        let nav = NativeTextPageNavigator()
        let longText = (0..<500).map { _ in "This is a line." }.joined(separator: "\n")
        nav.paginate(text: longText, font: defaultFont, viewportSize: phoneViewport)

        // Offset 0 should be on page 0
        let page = nav.pageContainingOffset(utf16Offset: 0)
        #expect(page == 0)
    }
}

@MainActor
private final class PageNavDelegateSpy: PageNavigatorDelegate {
    var navigatedPages: [Int] = []

    func pageNavigator(_ navigator: any PageNavigator, didNavigateToPage page: Int) {
        navigatedPages.append(page)
    }
}

// MARK: - AutoPageTurner + NativeTextPageNavigator Integration

@Suite("AutoPageTurner + NativeTextPageNavigator Integration")
@MainActor
struct AutoPageTurnerIntegrationTests {

    @Test func autoTurner_worksWithNativeTextPageNavigator() {
        let nav = NativeTextPageNavigator()
        let longText = (0..<500).map { _ in "This is a line." }.joined(separator: "\n")
        nav.paginate(
            text: longText,
            font: UIFont.systemFont(ofSize: 17),
            viewportSize: CGSize(width: 375, height: 667)
        )

        let turner = AutoPageTurner()
        turner.start(navigator: nav)
        #expect(turner.state == .running)
        turner.stop()
    }

    @Test func autoTurner_stopsOnUserInteraction_pause() {
        let nav = NativeTextPageNavigator()
        let longText = (0..<500).map { _ in "Line." }.joined(separator: "\n")
        nav.paginate(
            text: longText,
            font: UIFont.systemFont(ofSize: 17),
            viewportSize: CGSize(width: 375, height: 667)
        )

        let turner = AutoPageTurner()
        turner.start(navigator: nav)
        turner.pause()
        #expect(turner.state == .paused)
        turner.stop()
    }
}

#endif
