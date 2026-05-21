// Purpose: Feature #62 WI-4 — `HighlightCardV3` (the passage card) for
// `HighlightsSheet`'s unified card stream, plus the shared `HighlightSwatch`
// colour map and `AnnotationCardDateFormatter`.
//
// The committed #860 design (`vreader-notes-unified.jsx`) renders two card
// kinds: `HighlightCardV3` here (a quoted highlight with an optional note
// block, visually identical to the v2 design) and `StandaloneNoteCard` (the
// note body is the hero), which lives in `StandaloneNoteCard.swift` (split
// for the ~300-line guideline). `HighlightsSheet` switches on
// `AnnotationStreamItem` to pick the card.
//
// The card `onJump` navigates to the locator — editing a highlight's note is
// `HighlightActionPopover`'s job (feature #64). Bug #249 / GH #1080 added the
// optional `metaTrailing` (the ⋯ button) + `bodyOverride` (the confirm strip
// / error chip) slots; both default to empty so the resting layout is
// unchanged.
//
// @coordinates-with: HighlightsSheet.swift, StandaloneNoteCard.swift,
//   HighlightsSheet+Delete.swift, AnnotationStreamItem.swift,
//   ReaderThemeV2.swift, HighlightRecord.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-unified.jsx`

import SwiftUI

/// The highlight-colour → swatch-colour map for `HighlightsSheet`'s
/// cards.
///
/// The committed #860 design (`vreader-notes-unified.jsx` `colorMap`)
/// depicts four swatch colours (yellow/green/blue/pink) with exact hex
/// stops. But the REAL stored highlight palette is broader —
/// red/orange/purple are also valid stored colour names. Mapping every
/// non-designed name to yellow would render a red/orange/purple
/// highlight with the wrong swatch + rule colour, a visible
/// data-fidelity regression. So this resolves the designed four to the
/// committed `NamedHighlightColor` hex stops, and the broader three to
/// their natural opaque hue — the same faithful-to-data strategy
/// `NoteCalloutView.noteSwatchColor` already established (rule 51
/// permits extending a designed swatch's data mapping). Unknown / empty
/// / legacy-hex values fall back to yellow — never `.clear`, never a
/// crash.
enum HighlightSwatch {
    static func color(for name: String) -> Color {
        let normalized = name.lowercased()
        // Designed four — pinned to the committed design hex stops.
        if let named = NamedHighlightColor.from(storageString: normalized),
           let color = Color(readerHexString: named.hex) {
            return color
        }
        // Broader stored palette the design did not depict.
        switch normalized {
        case "red":    return Color(readerHexString: "#e08585") ?? .red
        case "orange": return Color(readerHexString: "#e8a85a") ?? .orange
        case "purple": return Color(readerHexString: "#b48ce8") ?? .purple
        default:
            return Color(readerHexString: NamedHighlightColor.yellow.hex) ?? .yellow
        }
    }
}

// MARK: - HighlightCardV3

/// The passage card — a colour-swatch meta row, a serif-italic quoted
/// passage with a 2pt solid colour left-rule, and (when the highlight
/// carries a non-empty note) a note block beneath. JSX `HighlightCardV3`.
///
/// Bug #249 — `metaTrailing` is an optional accessory rendered inline AFTER
/// the date in the meta row (the design's trailing `⋯` button). It defaults
/// to an empty view, so the resting layout is unchanged when no accessory is
/// supplied.
struct HighlightCardV3<MetaTrailing: View, BodyOverride: View>: View {
    let theme: ReaderThemeV2
    let highlight: HighlightRecord
    /// Meta sub-line — `chapter · p. N` — pre-composed by `HighlightsSheet`.
    let metaLabel: String
    let onJump: (Locator) -> Void
    /// Optional trailing accessory in the meta row (the ⋯ button).
    let metaTrailing: () -> MetaTrailing
    /// Body replacement — when `usesBodyOverride` is true, this replaces the
    /// passage + note region (Bug #249's confirm strip / error chip). The
    /// meta row stays so the user sees WHICH row they are acting on.
    let bodyOverride: () -> BodyOverride
    /// Whether `bodyOverride` is active. An explicit flag (not a static-type
    /// check) because the supplied closure is always a `_ConditionalContent`
    /// wrapper, never literally `EmptyView`.
    let usesBodyOverride: Bool
    /// Whether tapping the row navigates. The sheet sets this `false` while a
    /// non-default interaction (menu / confirm / swipe) owns the row — the
    /// design disables jump then (Bug #249).
    let jumpEnabled: Bool

    init(
        theme: ReaderThemeV2,
        highlight: HighlightRecord,
        metaLabel: String = "",
        onJump: @escaping (Locator) -> Void,
        usesBodyOverride: Bool = false,
        jumpEnabled: Bool = true,
        @ViewBuilder metaTrailing: @escaping () -> MetaTrailing = { EmptyView() },
        @ViewBuilder bodyOverride: @escaping () -> BodyOverride = { EmptyView() }
    ) {
        self.theme = theme
        self.highlight = highlight
        self.metaLabel = metaLabel
        self.onJump = onJump
        self.usesBodyOverride = usesBodyOverride
        self.jumpEnabled = jumpEnabled
        self.metaTrailing = metaTrailing
        self.bodyOverride = bodyOverride
    }

    /// True when the note block is part of the composition — the
    /// highlight carries a non-empty note (the design's `h.note` guard).
    var showsNoteBlock: Bool {
        highlight.note?.isEmpty == false
    }

    /// Test-only hook — invokes `onJump` with the highlight's locator.
    func invokeJumpForTesting() { onJump(highlight.locator) }

    private var swatch: Color { HighlightSwatch.color(for: highlight.color) }

    /// Navigate only when jump is enabled (suppressed while a row interaction
    /// is active, so an outside-tap dismisses rather than navigates).
    private func tryJump() { if jumpEnabled { onJump(highlight.locator) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metaRow
            if usesBodyOverride {
                bodyOverride()
            } else {
                passage
                    .contentShape(Rectangle())
                    .onTapGesture { tryJump() }
                if showsNoteBlock, let note = highlight.note {
                    noteBlock(note)
                        .contentShape(Rectangle())
                        .onTapGesture { tryJump() }
                }
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
            RoundedRectangle(cornerRadius: 2)
                .fill(swatch)
                .frame(width: 10, height: 10)
            Text(metaLabel)
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
            Spacer(minLength: 0)
            Text(AnnotationCardDateFormatter.medium.string(from: highlight.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
            metaTrailing()
        }
        .contentShape(Rectangle())
        .onTapGesture { tryJump() }
    }

    @ViewBuilder
    private var passage: some View {
        Text("\u{201C}\(highlight.selectedText)\u{201D}")
            .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14.5)))
            .italic()
            .foregroundStyle(Color(theme.inkColor))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle().fill(swatch).frame(width: 2)
            }
    }

    @ViewBuilder
    private func noteBlock(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "note.text")
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
                .padding(.top, 2)
            Text(note)
                .font(.system(size: 13))
                .foregroundStyle(Color(theme.subColor))
                .lineSpacing(2)
        }
        .padding(.leading, 14)
    }

}

/// The shared medium-date formatter both annotation cards use for the
/// meta-row date. Non-generic (lives at file scope, not on the now-generic
/// `HighlightCardV3`) so a single instance is reused across both card kinds
/// and any specialization (Bug #249 made the cards generic over the trailing
/// accessory).
enum AnnotationCardDateFormatter {
    static let medium: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
