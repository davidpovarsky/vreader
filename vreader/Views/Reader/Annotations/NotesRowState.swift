// Purpose: Bug #249 / GH #1080 — the pure row-interaction state machine for
// `HighlightsSheet`'s delete affordance.
//
// The committed design (`dev-docs/designs/vreader-fidelity-v1/project/
// vreader-notes-delete.jsx`, `HighlightsSheetV4`) puts the per-row
// interaction state on the SHEET, not the card, so that at most ONE row can
// be in a non-default phase at any moment (a menu open on row A collapses
// when the user taps the ⋯ on row B; opening the confirm strip on one row
// dismisses any other row's menu). `NotesRowState` is that single source of
// truth: an optional active row id paired with its phase.
//
// Foundation-only — no SwiftUI — so the transition logic is unit-testable
// without a render path (the `AnnotationStreamItem` / `ReaderMoreMenuEffect`
// pure-logic-type precedent).
//
// @coordinates-with: HighlightsSheet.swift, NotesActionMenu.swift,
//   HighlightAnnotationCard.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-delete.jsx`

import Foundation

/// The interaction phase a single notes/highlights row can be in. Mirrors
/// the design's `HighlightCardV4` `state` prop
/// (`'default' | 'menu-open' | 'confirming' | 'deleting' | 'error' |
/// 'swipe-revealed'`).
///
/// The design's `'dim-after-delete'` transient is intentionally NOT modelled:
/// `removeHighlight` / `removeAnnotation` remove the record from the view
/// model's in-memory array as part of the delete, so on success the row
/// leaves `currentStream` immediately and the `LazyVStack` drops it — there is
/// no row left to dim. Honouring the visible dim would require deferring the
/// view model's array removal, which is out of scope for the delete-affordance
/// fix.
enum NotesRowPhase: Equatable, Sendable {
    /// Resting — tap-to-jump, ⋯ button visible.
    case `default`
    /// The ⋯ action menu (Edit · Copy · Delete) is open over this row.
    case menuOpen
    /// The inline delete-confirmation strip (`NotesDeleteConfirm`) is shown.
    case confirming
    /// The persistence delete is in flight — a spinner replaces the ⋯ slot.
    case deleting
    /// The delete failed — the row shows the `NotesRowError` chip
    /// (Retry + Undo).
    case error
    /// The left-swipe drawer (Edit + Delete) is revealed by a drag gesture.
    case swipeRevealed
}

/// `HighlightsSheet`'s single per-row interaction state — the active row's
/// id (or `nil` when every row is at rest) and that row's phase.
///
/// SHEET-owned, so exactly one row is ever non-default. All transitions are
/// pure functions that return a new value; the sheet stores the result in
/// `@State`. The design's `HighlightsSheetV4.handlers` closures map 1:1 to
/// the mutating helpers below.
struct NotesRowState: Equatable, Sendable {
    /// The row currently in a non-default phase, or `nil` when all rows rest.
    private(set) var activeRowId: UUID?
    /// The active row's phase. `.default` whenever `activeRowId` is `nil`.
    private(set) var phase: NotesRowPhase

    /// The all-rest state — every row tap-to-jump, no menu / confirm / swipe.
    static let resting = NotesRowState(activeRowId: nil, phase: .default)

    init(activeRowId: UUID? = nil, phase: NotesRowPhase = .default) {
        // Invariant: a nil row id always pairs with `.default`. A non-default
        // phase requires an owning row.
        if activeRowId == nil {
            self.activeRowId = nil
            self.phase = .default
        } else {
            self.activeRowId = activeRowId
            self.phase = phase
        }
    }

    /// The phase to render for `rowId` — the stored `phase` when `rowId` is
    /// the active row, `.default` for every other row. This is what each
    /// card binds to (the design's `stateFor(id)`).
    func phase(for rowId: UUID) -> NotesRowPhase {
        activeRowId == rowId ? phase : .default
    }

    /// True when `rowId` is the active, non-default row.
    func isActive(_ rowId: UUID) -> Bool {
        activeRowId == rowId && phase != .default
    }

    // MARK: - Transitions (pure — return the next state)

    /// Open the ⋯ action menu over `rowId`. Supersedes any other row's
    /// active phase (the design's "only one row non-default").
    func openingMenu(for rowId: UUID) -> NotesRowState {
        NotesRowState(activeRowId: rowId, phase: .menuOpen)
    }

    /// Begin delete confirmation on `rowId` — the inline confirm strip.
    /// Reached from the menu's Delete item OR the swipe drawer's Delete cell.
    func confirmingDelete(for rowId: UUID) -> NotesRowState {
        NotesRowState(activeRowId: rowId, phase: .confirming)
    }

    /// Reveal the left-swipe drawer (Edit + Delete) on `rowId`.
    func revealingSwipe(for rowId: UUID) -> NotesRowState {
        NotesRowState(activeRowId: rowId, phase: .swipeRevealed)
    }

    /// Commit the delete — the spinner phase while the `PersistenceActor`
    /// call is in flight.
    func deleting(_ rowId: UUID) -> NotesRowState {
        NotesRowState(activeRowId: rowId, phase: .deleting)
    }

    /// The delete failed — show the error chip on `rowId`.
    func failed(_ rowId: UUID) -> NotesRowState {
        NotesRowState(activeRowId: rowId, phase: .error)
    }

    /// Return every row to rest (Cancel, Undo, menu scrim tap, a completed
    /// jump/copy/edit handoff, or a finished delete). The design's
    /// `onCancelDelete` / `onClose`.
    func dismissed() -> NotesRowState {
        .resting
    }
}
