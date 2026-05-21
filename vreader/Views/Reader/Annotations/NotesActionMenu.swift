// Purpose: Bug #249 / GH #1080 — the ⋯ button + action-menu surfaces for
// `HighlightsSheet`'s cards, translated from the committed design
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-delete.jsx`.
//
// This file holds the menu-side pieces (all SHEET-driven — state lives on
// `HighlightsSheet`):
//   - `NotesActionKind` — the highlight-vs-standalone distinction the labels
//     and confirm copy switch on (`'highlight'` / `'standalone'`).
//   - `NotesDeleteInk` — the shared destructive / amber inks (identical to
//     `HighlightPopoverDeleteConfirm`'s, so the review-sheet and in-reader
//     delete surfaces match).
//   - `NotesMoreButton` — the trailing ⋯ icon button in each card's meta row
//     (JSX `NotesMoreButton`). The canonical, discoverable, accessible
//     affordance.
//   - `NotesActionMenu` — the Edit · Copy · Delete popover anchored to the ⋯
//     button (JSX `NotesActionMenu`). Delete carries destructive ink + a
//     divider above it.
//
// The body-replacement / trailing surfaces (`NotesDeleteConfirm`,
// `NotesRowError`, `NotesSwipeActions`) live in `NotesDeleteConfirm.swift`.
//
// @coordinates-with: HighlightAnnotationCard.swift, HighlightsSheet.swift,
//   NotesDeleteConfirm.swift, NotesRowState.swift,
//   HighlightPopoverDeleteConfirm.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-delete.jsx`

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Which card kind a notes-row action applies to — drives the menu labels
/// and the confirm-strip copy (JSX `kind`).
enum NotesActionKind: Equatable, Sendable {
    case highlight
    case standalone
}

// MARK: - Shared destructive ink

/// The destructive ink the delete affordance uses — pinned to the committed
/// design's `ndDanger(t)` (and identical to `HighlightPopoverDeleteConfirm`'s
/// `dangerColor`, so the review-sheet and in-reader-popover delete surfaces
/// match exactly).
enum NotesDeleteInk {
    static func danger(_ theme: ReaderThemeV2) -> Color {
        Color(theme.isDark
            ? UIColor(red: 0.91, green: 0.56, blue: 0.56, alpha: 1)   // #e89090
            : UIColor(red: 0.66, green: 0.23, blue: 0.23, alpha: 1))  // #a83a3a
    }

    /// The swipe-drawer Edit cell's amber — the design's `ndAmber(t)`.
    static func amber(_ theme: ReaderThemeV2) -> Color {
        Color(theme.isDark
            ? UIColor(red: 0.878, green: 0.659, blue: 0.353, alpha: 1) // #e0a85a
            : UIColor(red: 0.659, green: 0.455, blue: 0.165, alpha: 1)) // #a8742a
    }
}

// MARK: - Trailing ⋯ button

/// The trailing ⋯ icon button — the canonical visible affordance. Lives in
/// the meta row AFTER the date as a 28×28 target (the design's
/// `NotesMoreButton`). Stays visible at rest so it's discoverable on a touch
/// device; sized to a 44×44 hit target via `.contentShape` for the HIG /
/// accessibility minimum while keeping the designed 16pt glyph.
struct NotesMoreButton: View {
    let theme: ReaderThemeV2
    let isActive: Bool
    let accessibilityLabel: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(theme.subColor))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(activeBackground)
                )
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("notesRowMoreButton")
    }

    private var activeBackground: Color {
        guard isActive else { return .clear }
        return Color.primary.opacity(theme.isDark ? 0.10 : 0.07)
    }
}

// MARK: - Action menu (Edit · Copy · Delete)

/// The small popover anchored to the ⋯ button — three items, Delete last
/// with destructive ink and a divider above it (the design's
/// `NotesActionMenu`). Labels switch on `kind`.
struct NotesActionMenu: View {
    let theme: ReaderThemeV2
    let kind: NotesActionKind
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var editLabel: String { kind == .standalone ? "Edit note" : "Edit note…" }
    private var copyLabel: String { kind == .standalone ? "Copy note" : "Copy quote" }
    private var deleteLabel: String { kind == .standalone ? "Delete note" : "Delete highlight" }

    var body: some View {
        VStack(spacing: 0) {
            menuItem(editLabel, systemImage: "pencil", action: onEdit,
                     identifier: "notesActionEdit")
            menuItem(copyLabel, systemImage: "doc.on.doc", action: onCopy,
                     identifier: "notesActionCopy")
            menuItem(deleteLabel, systemImage: "trash", action: onDelete,
                     isDestructive: true, hasDivider: true,
                     identifier: "notesActionDelete")
        }
        .frame(width: 184)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(surfaceColor)
                .shadow(color: .black.opacity(0.28), radius: 15, x: 0, y: 14)
        )
        .accessibilityIdentifier("notesActionMenu")
    }

    @ViewBuilder
    private func menuItem(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void,
        isDestructive: Bool = false,
        hasDivider: Bool = false,
        identifier: String
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13.5, weight: isDestructive ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isDestructive ? NotesDeleteInk.danger(theme) : Color(theme.inkColor))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if hasDivider {
                    Rectangle().fill(Color(theme.ruleColor)).frame(height: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var surfaceColor: Color {
        Color(theme.isDark
            ? UIColor(red: 0.184, green: 0.173, blue: 0.157, alpha: 1)   // #2f2c28
            : UIColor(red: 0.992, green: 0.976, blue: 0.925, alpha: 1))  // #fdf9ec
    }
}

#endif
