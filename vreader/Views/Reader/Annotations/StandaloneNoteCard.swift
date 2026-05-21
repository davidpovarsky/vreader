// Purpose: Bug #249 / GH #1080 (split from `HighlightAnnotationCard.swift`) —
// `StandaloneNoteCard`, the standalone-note card in `HighlightsSheet`'s
// unified card stream, plus its `DashedVerticalRule` accent.
//
// Split out of `HighlightAnnotationCard.swift` to keep both card files under
// the ~300-line guideline (`.claude/rules/50-codebase-conventions.md` §9)
// after Bug #249 made the cards generic over the trailing ⋯ accessory + the
// confirm/error body override. `HighlightCardV3` (the passage card),
// `HighlightSwatch`, and `AnnotationCardDateFormatter` stay in
// `HighlightAnnotationCard.swift`.
//
// JSX `StandaloneNoteCard` (the design's standalone-note card).
//
// @coordinates-with: HighlightAnnotationCard.swift, HighlightsSheet.swift,
//   HighlightsSheet+Delete.swift, AnnotationStreamItem.swift,
//   ReaderThemeV2.swift, AnnotationRecord.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-unified.jsx`

import SwiftUI

// MARK: - StandaloneNoteCard

/// The standalone-note card — a note-glyph pictogram meta row with a
/// `Standalone` pill, and the note body as the hero behind a 2pt DASHED
/// accent left-rule (no colour swatch — no highlight backs it). JSX
/// `StandaloneNoteCard`.
///
/// Bug #249 — `metaTrailing` is an optional accessory rendered inline AFTER
/// the date (the design's ⋯ button); defaults to empty so the resting layout
/// is unchanged when no accessory is supplied.
struct StandaloneNoteCard<MetaTrailing: View, BodyOverride: View>: View {
    let theme: ReaderThemeV2
    let note: AnnotationRecord
    /// Meta sub-line — `chapter · p. N` — pre-composed by `HighlightsSheet`.
    let metaLabel: String
    let onJump: (Locator) -> Void
    /// Optional trailing accessory in the meta row (the ⋯ button).
    let metaTrailing: () -> MetaTrailing
    /// Body replacement — replaces the note body when `usesBodyOverride` is
    /// true (Bug #249's confirm strip / error chip).
    let bodyOverride: () -> BodyOverride
    /// Whether `bodyOverride` is active (an explicit flag, not a static-type
    /// check — the supplied closure is always a `_ConditionalContent` wrapper).
    let usesBodyOverride: Bool
    /// Whether tapping the row navigates. The sheet sets this `false` while a
    /// non-default interaction (menu / confirm / swipe) owns the row (Bug #249).
    let jumpEnabled: Bool

    init(
        theme: ReaderThemeV2,
        note: AnnotationRecord,
        metaLabel: String = "",
        onJump: @escaping (Locator) -> Void,
        usesBodyOverride: Bool = false,
        jumpEnabled: Bool = true,
        @ViewBuilder metaTrailing: @escaping () -> MetaTrailing = { EmptyView() },
        @ViewBuilder bodyOverride: @escaping () -> BodyOverride = { EmptyView() }
    ) {
        self.theme = theme
        self.note = note
        self.metaLabel = metaLabel
        self.onJump = onJump
        self.usesBodyOverride = usesBodyOverride
        self.jumpEnabled = jumpEnabled
        self.metaTrailing = metaTrailing
        self.bodyOverride = bodyOverride
    }

    /// Test-only hook — invokes `onJump` with the annotation's locator.
    func invokeJumpForTesting() { onJump(note.locator) }

    /// Navigate only when jump is enabled (suppressed while a row interaction
    /// is active, so an outside-tap dismisses rather than navigates).
    private func tryJump() { if jumpEnabled { onJump(note.locator) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metaRow
            if usesBodyOverride {
                bodyOverride()
            } else {
                body_
                    .contentShape(Rectangle())
                    .onTapGesture { tryJump() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(theme.ruleColor)).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 8) {
            // Standalone pictogram — a small filled note glyph in an
            // accent-tinted rounded square (no colour swatch).
            Image(systemName: "note.text")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color(theme.accentColor))
                .frame(width: 12, height: 12)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(theme.accentColor).opacity(0.13))
                )
            Text(metaLabel)
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
            Text("Standalone")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color(theme.subColor))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(Color.primary.opacity(theme.isDark ? 0.06 : 0.05))
                )
            Spacer(minLength: 0)
            Text(AnnotationCardDateFormatter.medium.string(from: note.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
            metaTrailing()
        }
        .contentShape(Rectangle())
        .onTapGesture { tryJump() }
    }

    @ViewBuilder
    private var body_: some View {
        Text(note.content)
            .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14.5)))
            .foregroundStyle(Color(theme.inkColor))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                // Dashed accent rule — distinguishes a standalone note
                // from a highlight's solid colour rule. A top-to-bottom
                // dashed line, 2pt wide.
                DashedVerticalRule(color: Color(theme.accentColor).opacity(0.53))
                    .frame(width: 2)
            }
    }
}

// MARK: - Dashed vertical rule

/// A 2pt top-to-bottom dashed line — the standalone-note card's accent
/// left-rule (the design's `borderLeft: 2px dashed`).
private struct DashedVerticalRule: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 1, y: 0))
                p.addLine(to: CGPoint(x: 1, y: geo.size.height))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        }
    }
}
