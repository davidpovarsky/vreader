// Purpose: Bug #249 / GH #1080 — pins `NotesRowState`, the pure per-row
// interaction state machine for `HighlightsSheet`'s delete affordance.
//
// Guards the design invariant that AT MOST ONE row is ever non-default
// (`vreader-notes-delete.jsx` `HighlightsSheetV4` — sheet-owned `rowState`):
// opening a menu / confirm / swipe on one row collapses any other row; a nil
// active id always renders `.default`; every transition is pure.
//
// @coordinates-with: NotesRowState.swift, HighlightsSheet.swift

import Testing
import Foundation
@testable import vreader

@Suite("Bug #249 — NotesRowState")
struct NotesRowStateTests {

    private let rowA = UUID()
    private let rowB = UUID()

    // MARK: - Resting / invariants

    @Test("Resting state has no active row and renders default for any row")
    func restingIsAllDefault() {
        let s = NotesRowState.resting
        #expect(s.activeRowId == nil)
        #expect(s.phase == .default)
        #expect(s.phase(for: rowA) == .default)
        #expect(s.isActive(rowA) == false)
    }

    @Test("A nil active id always pairs with the default phase (invariant)")
    func nilIdForcesDefault() {
        // Even if a caller tries to construct a non-default phase with no
        // owning row, the invariant collapses it to resting.
        let s = NotesRowState(activeRowId: nil, phase: .confirming)
        #expect(s.activeRowId == nil)
        #expect(s.phase == .default)
    }

    // MARK: - Per-row phase projection

    @Test("phase(for:) returns the stored phase only for the active row")
    func phaseProjectionIsRowScoped() {
        let s = NotesRowState.resting.openingMenu(for: rowA)
        #expect(s.phase(for: rowA) == .menuOpen)
        // Every other row stays default.
        #expect(s.phase(for: rowB) == .default)
        #expect(s.isActive(rowA))
        #expect(s.isActive(rowB) == false)
    }

    // MARK: - Transitions

    @Test("openingMenu activates the row in the menu-open phase")
    func openingMenuActivates() {
        let s = NotesRowState.resting.openingMenu(for: rowA)
        #expect(s.activeRowId == rowA)
        #expect(s.phase == .menuOpen)
    }

    @Test("confirmingDelete moves the row to the confirm phase")
    func confirmingDelete() {
        let s = NotesRowState.resting.openingMenu(for: rowA).confirmingDelete(for: rowA)
        #expect(s.activeRowId == rowA)
        #expect(s.phase == .confirming)
    }

    @Test("deleting / failed / swipe each set the matching phase")
    func phaseHelpers() {
        #expect(NotesRowState.resting.deleting(rowA).phase == .deleting)
        #expect(NotesRowState.resting.failed(rowA).phase == .error)
        #expect(NotesRowState.resting.revealingSwipe(for: rowA).phase == .swipeRevealed)
    }

    @Test("dismissed returns to resting from any phase")
    func dismissedResets() {
        let s = NotesRowState.resting.openingMenu(for: rowA).confirmingDelete(for: rowA)
        let dismissed = s.dismissed()
        #expect(dismissed == .resting)
        #expect(dismissed.phase(for: rowA) == .default)
    }

    // MARK: - Single-active-row invariant (the design's core rule)

    @Test("Opening a menu on row B supersedes an active confirm on row A")
    func openingMenuSupersedesOtherRow() {
        // Row A is mid-confirm; the user taps the ⋯ on row B.
        let s = NotesRowState.resting
            .openingMenu(for: rowA)
            .confirmingDelete(for: rowA)
            .openingMenu(for: rowB)
        // Only row B is active now; row A is back to default.
        #expect(s.activeRowId == rowB)
        #expect(s.phase == .menuOpen)
        #expect(s.phase(for: rowA) == .default)
        #expect(s.phase(for: rowB) == .menuOpen)
        #expect(s.isActive(rowA) == false)
    }

    @Test("Confirm on a different row supersedes a prior menu")
    func confirmOnOtherRowSupersedes() {
        let s = NotesRowState.resting
            .openingMenu(for: rowA)
            .confirmingDelete(for: rowB)
        #expect(s.activeRowId == rowB)
        #expect(s.phase == .confirming)
        #expect(s.phase(for: rowA) == .default)
    }

    @Test("Swipe on one row supersedes another row's swipe")
    func swipeSupersedesSwipe() {
        let s = NotesRowState.resting
            .revealingSwipe(for: rowA)
            .revealingSwipe(for: rowB)
        #expect(s.isActive(rowB))
        #expect(s.phase(for: rowA) == .default)
    }
}
