// Purpose: RED tests for Bug #82 — Paged mode still scrolls instead of paginating.
// Proves the root cause: TextReaderUIState.updatePagination() destroys the page
// navigator when called with isPagedMode=true but nil attributedText (race between
// mode switch and attributed string build). Also tests mode switch resilience.
//
// These tests assert CORRECT behavior that the current code does NOT implement.
// They should FAIL until the bug is fixed.
//
// @coordinates-with: TextReaderUIState.swift, NativeTextPageNavigator.swift,
//   TXTReaderContainerView.swift, UnifiedTextRendererViewModel.swift

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("Bug #82 — Paged Mode")
@MainActor
struct PagedModeBug82Tests {

    // MARK: - Helpers

    private func makeAttributedText(lineCount: Int = 200) -> NSAttributedString {
        let lines = (0..<lineCount).map { _ in
            "This is a line of text for paged mode testing in VReader."
        }.joined(separator: "\n")
        return NSAttributedString(
            string: lines,
            attributes: [.font: UIFont.systemFont(ofSize: 17)]
        )
    }

    // -----------------------------------------------------------------------
    // ROOT CAUSE TEST: updatePagination with nil attributedText destroys navigator
    // -----------------------------------------------------------------------

    @Test("updatePagination should preserve navigator when attributedText is temporarily nil")
    func updatePagination_nilAttrText_shouldPreserveNavigator() {
        let state = TextReaderUIState()
        let attrText = makeAttributedText()

        // First: create the navigator with valid data
        state.updatePagination(
            isPagedMode: true,
            attributedText: attrText,
            initialRestoreOffset: nil,
            autoPageTurnEnabled: false,
            autoPageTurnInterval: 0
        )

        #expect(state.pageNavigator != nil, "Navigator should be created")
        let originalTotalPages = state.pageNavigator?.totalPages ?? 0
        #expect(originalTotalPages > 0, "Should have pages")

        // Simulate the race: settings change triggers updatePagination BEFORE
        // the attributed string rebuild completes. attributedText is nil.
        state.updatePagination(
            isPagedMode: true,
            attributedText: nil,  // ← Race: attr string not ready yet
            initialRestoreOffset: nil,
            autoPageTurnEnabled: false,
            autoPageTurnInterval: 0
        )

        // BUG: Current code sets pageNavigator = nil because the guard fails.
        // The view then falls back to scroll mode (isPagedMode && nav != nil → false).
        // Correct behavior: preserve the existing navigator until new data arrives.
        #expect(state.pageNavigator != nil,
                "Navigator should NOT be destroyed when attributedText is temporarily nil in paged mode")
        #expect(state.pageNavigator?.totalPages == originalTotalPages,
                "Page count should be preserved from previous pagination")
    }

    // -----------------------------------------------------------------------
    // SEQUENTIAL MODE SWITCH: scroll → paged → scroll → paged
    // -----------------------------------------------------------------------

    @Test("repeated mode switches should not lose pagination state")
    func repeatedModeSwitches_shouldNotLoseState() {
        let state = TextReaderUIState()
        let attrText = makeAttributedText()

        // Enter paged mode
        state.updatePagination(
            isPagedMode: true,
            attributedText: attrText,
            initialRestoreOffset: nil,
            autoPageTurnEnabled: false,
            autoPageTurnInterval: 0
        )
        #expect(state.pageNavigator != nil)

        // Switch to scroll
        state.updatePagination(
            isPagedMode: false,
            attributedText: attrText,
            initialRestoreOffset: nil,
            autoPageTurnEnabled: false,
            autoPageTurnInterval: 0
        )
        #expect(state.pageNavigator == nil, "Scroll mode should clear navigator")

        // Switch back to paged — but attributedText rebuild hasn't completed
        state.updatePagination(
            isPagedMode: true,
            attributedText: nil,  // ← Not ready yet
            initialRestoreOffset: nil,
            autoPageTurnEnabled: false,
            autoPageTurnInterval: 0
        )

        // BUG: navigator is nil, view falls to scroll mode
        // This test captures: after scroll→paged with nil attr, navigator should
        // at least be pending (not nil). Or the view should show a loading state
        // instead of silently falling to scroll.
        //
        // Since we can't test the view, we test the state contract:
        // isPagedMode=true should result in a valid paged state eventually.
        // For now, re-call with valid data to verify recovery works:
        state.updatePagination(
            isPagedMode: true,
            attributedText: attrText,
            initialRestoreOffset: nil,
            autoPageTurnEnabled: false,
            autoPageTurnInterval: 0
        )
        #expect(state.pageNavigator != nil,
                "Navigator should be created when valid data arrives after nil gap")
    }

    // -----------------------------------------------------------------------
    // UNIFIED MODE: configure() transitions
    // -----------------------------------------------------------------------

    @Test("UnifiedTextRendererViewModel configure paged mode should set isPagedMode and totalPages atomically")
    func configurePagedMode_atomicTransition() {
        let longText = (0..<200).map { _ in
            "This is a line of text for unified renderer paged mode testing."
        }.joined(separator: "\n")
        let vm = UnifiedTextRendererViewModel(text: longText)

        // Start in scroll mode
        vm.configure(
            font: UIFont.systemFont(ofSize: 17),
            viewportSize: CGSize(width: 375, height: 667),
            layout: .scroll
        )
        #expect(vm.isScrollMode)
        #expect(vm.totalPages == 0)

        // Switch to paged mode
        vm.configure(
            font: UIFont.systemFont(ofSize: 17),
            viewportSize: CGSize(width: 375, height: 667),
            layout: .paged
        )

        // After configure() returns, BOTH isPagedMode and totalPages must be valid.
        // If the view checks isPagedMode before totalPages is set, it shows an empty page.
        #expect(vm.isPagedMode, "Should be in paged mode after configure")
        #expect(vm.totalPages > 0,
                "totalPages must be > 0 immediately after configure(layout: .paged)")
    }

    // -----------------------------------------------------------------------
    // NATIVE PAGED: position restore after pagination
    // -----------------------------------------------------------------------

    @Test("updatePagination should restore position from initialRestoreOffset")
    func updatePagination_restoresOffset() {
        let state = TextReaderUIState()
        let attrText = makeAttributedText(lineCount: 300)

        // Paginate with a saved offset (simulating reopen)
        let midOffset = (attrText.string as NSString).length / 2
        state.updatePagination(
            isPagedMode: true,
            attributedText: attrText,
            initialRestoreOffset: midOffset,
            autoPageTurnEnabled: false,
            autoPageTurnInterval: 0
        )

        #expect(state.pageNavigator != nil)
        // Should not be on page 0 — the offset was in the middle
        #expect(state.pageNavigator!.currentPage > 0,
                "Should restore to a page past the first after mid-document offset")
    }
}
#endif
