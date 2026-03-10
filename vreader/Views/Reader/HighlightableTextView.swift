// Purpose: UITextView subclass with safe highlight rendering via custom HighlightingLayoutManager.
// Extracted from TXTTextViewBridge.swift (WI-001) — zero logic change.
//
// Key decisions:
// - HighlightingLayoutManager.drawBackground() draws highlight backgrounds without modifying
//   text storage — completely avoids the crash chain documented in bug #47 (v5–v12).
// - setSourceText() is the ONLY method that modifies text storage (initial load, config change).
// - setHighlightRanges() updates the layout manager only — safe during active selection.
//
// @coordinates-with TXTTextViewBridge.swift, TXTChunkedReaderBridge.swift

import UIKit

/// Custom layout manager that draws highlight backgrounds without modifying text storage.
/// This completely avoids the UITextView crash chain (bug #47 v5-v11) where ANY
/// text storage modification on a visible text view with active selection crashes:
/// - textStorage.addAttribute → accessibility recursion (v5)
/// - attributedText setter → accessibility traversal crash (v10)
/// - textStorage.setAttributedString → same crash, shorter stack (v11)
///
/// drawBackground() is called by UIKit's normal display pipeline for the visible
/// glyph range only — efficient, synchronized with scrolling, zero text storage mutation.
final class HighlightingLayoutManager: NSLayoutManager {

    /// Character ranges to draw as highlight backgrounds.
    var highlightRanges: [NSRange] = []
    private let highlightColor = UIColor.systemYellow.withAlphaComponent(0.4).cgColor

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard !highlightRanges.isEmpty,
              let ctx = UIGraphicsGetCurrentContext(),
              let tc = textContainers.first,
              let ts = textStorage else { return }

        let textLength = ts.length
        guard textLength > 0 else { return }
        let validBounds = NSRange(location: 0, length: textLength)

        let visibleCharRange = characterRange(
            forGlyphRange: glyphsToShow, actualGlyphRange: nil
        )

        for charRange in highlightRanges {
            // Clamp to text storage bounds — protects against stale/corrupted ranges
            let clamped = NSIntersectionRange(charRange, validBounds)
            guard clamped.length > 0 else { continue }
            guard NSIntersectionRange(clamped, visibleCharRange).length > 0 else { continue }
            let glyphRange = self.glyphRange(
                forCharacterRange: clamped, actualCharacterRange: nil
            )
            let visible = NSIntersectionRange(glyphRange, glyphsToShow)
            guard visible.length > 0 else { continue }

            ctx.setFillColor(highlightColor)
            enumerateEnclosingRects(
                forGlyphRange: visible,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: tc
            ) { rect, _ in
                ctx.fill(rect.offsetBy(dx: origin.x, dy: origin.y))
            }
        }
    }
}

/// UITextView subclass with safe highlight rendering (bug #47 v12).
///
/// v5-v11 tried every approach to modify text storage for highlights — all crashed.
/// v12 uses a custom HighlightingLayoutManager that draws highlight backgrounds
/// in drawBackground() — NEVER modifying text storage for highlights.
///
/// Text storage is only modified for source text changes (initial load, config
/// change) via setSourceText(), never during active selection.
final class HighlightableTextView: UITextView {

    /// Guard flag to suppress delegate callbacks during source text replacement.
    var isReplacingText = false

    /// Creates a text view with HighlightingLayoutManager for safe highlight drawing.
    convenience init() {
        let storage = NSTextStorage()
        let lm = HighlightingLayoutManager()
        let container = NSTextContainer()
        lm.addTextContainer(container)
        storage.addLayoutManager(lm)
        self.init(frame: .zero, textContainer: container)
    }

    /// Sets source text (for initial load and config changes only).
    /// Do NOT call for highlight-only changes — use setHighlightRanges instead.
    func setSourceText(_ attrText: NSAttributedString) {
        isReplacingText = true
        defer { isReplacingText = false }
        let savedOffset = contentOffset
        selectedTextRange = nil
        textStorage.setAttributedString(attrText)
        contentOffset = savedOffset
    }

    /// Updates highlight visualization via the layout manager's drawing layer.
    /// NEVER modifies text storage — completely avoids the crash chain (bug #47 v12).
    func setHighlightRanges(persisted: [NSRange], active: NSRange?) {
        guard let lm = layoutManager as? HighlightingLayoutManager else { return }
        var ranges = persisted
        if let active, active.length > 0,
           !ranges.contains(active) {
            ranges.append(active)
        }
        lm.highlightRanges = ranges
        let glyphCount = lm.numberOfGlyphs
        if glyphCount > 0 {
            lm.invalidateDisplay(forGlyphRange: NSRange(location: 0, length: glyphCount))
        }
    }
}
