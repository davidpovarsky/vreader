// Purpose: Bug #249 / GH #1080 — the inline confirm strip, error chip, and
// swipe drawer for `HighlightsSheet`'s delete affordance, translated from the
// committed design `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-notes-delete.jsx`.
//
// Split out of `NotesActionMenu.swift` to keep both files under the ~300-line
// guideline (`.claude/rules/50-codebase-conventions.md` §9). The ⋯ button +
// the Edit/Copy/Delete popover live in `NotesActionMenu.swift`; this file has
// the three body-replacement / trailing surfaces:
//   - `NotesDeleteConfirm` — inline confirm strip (mirrors `HPDeleteConfirm`).
//   - `NotesRowError` — failed-delete chip with Retry + Undo.
//   - `NotesSwipeActions` — the left-swipe Edit + Delete drawer.
//
// @coordinates-with: NotesActionMenu.swift, NotesDeleteRow.swift,
//   HighlightsSheet+Delete.swift, HighlightPopoverDeleteConfirm.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-delete.jsx`

#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - Inline delete-confirmation strip

/// Replaces the card's lead content with a tinted confirmation strip — the
/// design's `NotesDeleteConfirm`. Mirrors `HighlightPopoverDeleteConfirm`
/// (`HPDeleteConfirm`): names what's lost, paired Cancel / Delete buttons
/// with destructive ink, a spinner on the Delete button while busy.
struct NotesDeleteConfirm: View {
    let theme: ReaderThemeV2
    let kind: NotesActionKind
    let isBusy: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var isStandalone: Bool { kind == .standalone }
    private var danger: Color { NotesDeleteInk.danger(theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isStandalone ? "Delete this note?" : "Delete this highlight?")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(theme.inkColor))
                .padding(.bottom, 2)
            Text(isStandalone
                 ? "The note comes off the chapter. Can't be undone."
                 : "The color, the note, and the underline come off the page. Can't be undone.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(theme.subColor))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color(theme.inkColor))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(theme.ruleColor), lineWidth: 0.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .opacity(isBusy ? 0.4 : 1)
                .accessibilityIdentifier("notesDeleteCancel")

                Button(action: onConfirm) {
                    HStack(spacing: 6) {
                        if isBusy {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        }
                        Text(isBusy ? "Deleting…" : "Delete")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(danger))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityIdentifier("notesDeleteConfirm")
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
        .background(
            RoundedRectangle(cornerRadius: 10).fill(stripFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(stripStroke, lineWidth: 0.5)
        )
    }

    private var stripFill: Color {
        Color(theme.isDark
            ? UIColor(red: 0.91, green: 0.56, blue: 0.56, alpha: 0.06)
            : UIColor(red: 0.66, green: 0.23, blue: 0.23, alpha: 0.04))
    }

    private var stripStroke: Color {
        Color(theme.isDark
            ? UIColor(red: 0.91, green: 0.56, blue: 0.56, alpha: 0.22)
            : UIColor(red: 0.66, green: 0.23, blue: 0.23, alpha: 0.16))
    }
}

// MARK: - Failed-delete chip

/// Replaces the row's lead content with a tinted error chip + Retry + Undo —
/// the design's `NotesRowError`. Retry re-invokes the delete; Undo restores
/// the row to its pre-tap state (the persistence call did not commit).
struct NotesRowError: View {
    let theme: ReaderThemeV2
    let message: String
    let onRetry: () -> Void
    let onUndo: () -> Void

    private var danger: Color { NotesDeleteInk.danger(theme) }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(danger).frame(width: 18, height: 18)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color(theme.inkColor))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRetry) {
                Text("Retry")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(Capsule().stroke(Color(theme.ruleColor), lineWidth: 0.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("notesRowErrorRetry")
            Button(action: onUndo) {
                Text("Undo")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color(theme.subColor))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("notesRowErrorUndo")
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(
            RoundedRectangle(cornerRadius: 10).fill(chipFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(chipStroke, lineWidth: 0.5)
        )
    }

    private var chipFill: Color {
        Color(theme.isDark
            ? UIColor(red: 0.91, green: 0.56, blue: 0.56, alpha: 0.08)
            : UIColor(red: 0.66, green: 0.23, blue: 0.23, alpha: 0.06))
    }

    private var chipStroke: Color {
        Color(theme.isDark
            ? UIColor(red: 0.91, green: 0.56, blue: 0.56, alpha: 0.26)
            : UIColor(red: 0.66, green: 0.23, blue: 0.23, alpha: 0.20))
    }
}

// MARK: - Swipe-revealed action drawer

/// The trailing Edit + Delete cells revealed by a left-swipe — the design's
/// `NotesSwipeActions`. Edit is amber, Delete is destructive ink; each cell
/// is 64pt wide, 128pt together.
struct NotesSwipeActions: View {
    let theme: ReaderThemeV2
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            cell(systemImage: "pencil", label: "Edit",
                 background: NotesDeleteInk.amber(theme), action: onEdit,
                 identifier: "notesSwipeEdit")
            cell(systemImage: "trash", label: "Delete",
                 background: NotesDeleteInk.danger(theme), action: onDelete,
                 identifier: "notesSwipeDelete")
        }
    }

    @ViewBuilder
    private func cell(
        systemImage: String, label: String, background: Color,
        action: @escaping () -> Void, identifier: String
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.3)
            }
            .foregroundStyle(.white)
            .frame(width: 64)
            .frame(maxHeight: .infinity)
            .background(background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
#endif
