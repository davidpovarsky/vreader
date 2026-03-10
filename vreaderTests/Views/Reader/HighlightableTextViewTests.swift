// Purpose: Tests for HighlightableTextView and HighlightingLayoutManager.
// Validates highlight range updates, source text setting, and isReplacingText guard.

import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("HighlightableTextView")
struct HighlightableTextViewTests {

    // MARK: - HighlightingLayoutManager

    @Test @MainActor func layoutManagerStartsWithEmptyRanges() {
        let tv = HighlightableTextView()
        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.highlightRanges.isEmpty)
    }

    // MARK: - setHighlightRanges

    @Test @MainActor func setHighlightRangesUpdatesLayoutManager() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello World"))
        let persisted = [NSRange(location: 0, length: 5)]
        tv.setHighlightRanges(persisted: persisted, active: nil)

        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.highlightRanges.count == 1)
        #expect(lm.highlightRanges[0] == NSRange(location: 0, length: 5))
    }

    @Test @MainActor func setHighlightRangesIncludesActiveRange() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello World"))
        let persisted = [NSRange(location: 0, length: 5)]
        let active = NSRange(location: 6, length: 5)
        tv.setHighlightRanges(persisted: persisted, active: active)

        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.highlightRanges.count == 2)
        #expect(lm.highlightRanges[0] == NSRange(location: 0, length: 5))
        #expect(lm.highlightRanges[1] == NSRange(location: 6, length: 5))
    }

    @Test @MainActor func setHighlightRangesIgnoresZeroLengthActive() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello"))
        tv.setHighlightRanges(persisted: [], active: NSRange(location: 0, length: 0))

        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.highlightRanges.isEmpty)
    }

    @Test @MainActor func setHighlightRangesWithEmptyInputsClearsRanges() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello"))
        tv.setHighlightRanges(persisted: [NSRange(location: 0, length: 3)], active: nil)
        tv.setHighlightRanges(persisted: [], active: nil)

        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.highlightRanges.isEmpty)
    }

    // MARK: - setSourceText

    @Test @MainActor func setSourceTextSetsTextStorageContent() {
        let tv = HighlightableTextView()
        let text = NSAttributedString(string: "Test content")
        tv.setSourceText(text)

        #expect(tv.textStorage.string == "Test content")
    }

    @Test @MainActor func setSourceTextPreservesContentOffset() {
        let tv = HighlightableTextView()
        tv.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        tv.setSourceText(NSAttributedString(string: String(repeating: "Line\n", count: 100)))
        tv.contentOffset = CGPoint(x: 0, y: 50)

        tv.setSourceText(NSAttributedString(string: String(repeating: "Line\n", count: 100)))
        #expect(tv.contentOffset.y == 50)
    }

    // MARK: - isReplacingText guard

    @Test @MainActor func isReplacingTextStartsFalse() {
        let tv = HighlightableTextView()
        #expect(tv.isReplacingText == false)
    }

    @Test @MainActor func isReplacingTextResetsAfterSetSourceText() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "test"))
        #expect(tv.isReplacingText == false)
    }

    // MARK: - Bounds safety (audit fix)

    @Test @MainActor func setHighlightRangesDeduplicatesActiveMatchingPersisted() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello World"))
        let range = NSRange(location: 0, length: 5)
        tv.setHighlightRanges(persisted: [range], active: range)

        let lm = tv.layoutManager as! HighlightingLayoutManager
        // Active duplicates persisted — should not double-paint
        #expect(lm.highlightRanges.count == 1)
    }

    @Test @MainActor func outOfBoundsRangeDoesNotCrashDrawBackground() {
        let tv = HighlightableTextView()
        tv.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        tv.setSourceText(NSAttributedString(string: "Short"))
        // Range extends way past text storage length
        tv.setHighlightRanges(persisted: [NSRange(location: 0, length: 9999)], active: nil)

        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.highlightRanges.count == 1)
        // Force layout — this would crash without bounds clamping
        lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: 5))
    }

    // MARK: - Convenience init

    @Test @MainActor func convenienceInitCreatesHighlightingLayoutManager() {
        let tv = HighlightableTextView()
        #expect(tv.layoutManager is HighlightingLayoutManager)
    }

    @Test @MainActor func convenienceInitHasTextContainer() {
        let tv = HighlightableTextView()
        #expect(tv.textContainer.layoutManager === tv.layoutManager)
    }

}
