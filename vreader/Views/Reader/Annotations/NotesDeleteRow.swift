// Purpose: Bug #249 / GH #1080 — the per-row chrome wrapping each
// `HighlightsSheet` card with the committed delete affordance
// (`dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-delete.jsx`
// `HighlightCardV4` / `StandaloneNoteCardV4` shell).
//
// The wrapper composes around a fully-built card (which the sheet supplies
// with the trailing ⋯ accessory + the phase-appropriate body override):
//   - the left-swipe drawer (`NotesSwipeActions`) revealed behind the card by
//     a horizontal drag (SwiftUI `.swipeActions` needs a `List`, which the
//     design rejects — so the swipe is a custom `DragGesture` translate, the
//     same constraint feature #56 WI-15 documented);
//   - the ⋯ action menu (`NotesActionMenu`) overlaid top-trailing, gated by a
//     transparent scrim that dismisses on outside tap.
//
// Generic over the card `Content` so one wrapper serves both card kinds.
//
// @coordinates-with: HighlightsSheet.swift, HighlightsSheet+Delete.swift,
//   NotesActionMenu.swift, NotesRowState.swift, HighlightAnnotationCard.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-delete.jsx`

#if canImport(UIKit)
import SwiftUI

/// Wraps one card with its delete affordance — the swipe drawer behind and
/// the action menu (plus its dismiss scrim) overlaid.
struct NotesDeleteRow<Content: View>: View {
    let theme: ReaderThemeV2
    let kind: NotesActionKind
    let phase: NotesRowPhase
    let onMore: () -> Void
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onRevealSwipe: () -> Void
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    /// The trailing drawer width — two 64pt cells (`NotesSwipeActions`).
    private let drawerWidth: CGFloat = 128

    private var isSwipe: Bool { phase == .swipeRevealed }
    private var isMenu: Bool { phase == .menuOpen }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Trailing swipe drawer — behind the card, revealed by the slide.
            if isSwipe {
                HStack {
                    Spacer(minLength: 0)
                    NotesSwipeActions(theme: theme, onEdit: onEdit, onDelete: onDelete)
                        .frame(width: drawerWidth)
                }
            }

            content()
                .offset(x: isSwipe ? -drawerWidth : 0)
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isSwipe)
                .highPriorityGesture(swipeGesture)
                // Within-row dismiss scrim — layered ABOVE the card content
                // (so it catches a tap on the row) but BELOW the menu (so menu
                // items still receive taps). The card's own jump is already
                // suppressed (`jumpEnabled == false`) in non-default phases; the
                // scrim turns a row tap into a dismiss while the menu is open.
                .overlay {
                    if isMenu {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture { onDismiss() }
                            .accessibilityHidden(true)
                    }
                }

            // Action menu — anchored to the ⋯ button's corner (top-trailing),
            // ABOVE the dismiss scrim so its items stay tappable.
            if isMenu {
                NotesActionMenu(
                    theme: theme, kind: kind,
                    onEdit: onEdit, onCopy: onCopy, onDelete: onDelete
                )
                .padding(.top, 30)
                .padding(.trailing, 2)
                .transition(.scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
            }
        }
    }

    /// Left-swipe to reveal the drawer; swipe back (or any rightward drag) to
    /// dismiss it. Threshold is a third of the drawer width.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                // Only a horizontal drag dominated by leftward motion reveals.
                let horizontal = abs(value.translation.width) > abs(value.translation.height)
                guard horizontal else { return }
                if value.translation.width < -drawerWidth / 3, !isSwipe {
                    onRevealSwipe()
                } else if value.translation.width > drawerWidth / 3, isSwipe {
                    onDismiss()
                }
            }
    }
}
#endif
