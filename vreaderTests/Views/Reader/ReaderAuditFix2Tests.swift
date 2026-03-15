// Purpose: Tests for high-severity audit fixes (batch 2).
// Issue 1: PDF findString page filtering — search selections filtered to target page.
// Issue 2: PDF isSearchHighlighting flag — suppress selectionDidChange during search.
// Issue 3: EPUB locator navigation with progression — seekScrollFraction set.
// Issue 4: EPUB searchHighlightJS with progression — scroll before find.
//
// @coordinates-with: PDFViewBridge.swift, EPUBReaderContainerView.swift,
//   EPUBHighlightBridge.swift

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
@testable import vreader

// MARK: - Issue 2: isSearchHighlighting flag

@Suite("ReaderAuditFix2 — Issue 2: PDF search highlighting guard")
struct PDFSearchHighlightGuardTests {

    @Test("Coordinator isSearchHighlighting defaults to false")
    @MainActor func coordinatorDefaultsFalse() {
        let coordinator = PDFViewBridge.Coordinator()
        #expect(coordinator.isSearchHighlighting == false)
    }

    @Test("Coordinator isSearchHighlighting can be set to true and back")
    @MainActor func coordinatorFlagToggle() {
        let coordinator = PDFViewBridge.Coordinator()
        coordinator.isSearchHighlighting = true
        #expect(coordinator.isSearchHighlighting == true)
        coordinator.isSearchHighlighting = false
        #expect(coordinator.isSearchHighlighting == false)
    }
}

// MARK: - Issue 4: EPUB searchHighlightJS with progression

@Suite("ReaderAuditFix2 — Issue 4: EPUB search highlight with progression")
struct EPUBSearchHighlightProgressionTests {

    @Test("searchHighlightJS with nil progression does not scroll")
    func noScrollWhenNilProgression() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "hello", progression: nil)
        #expect(!js.isEmpty)
        #expect(js.contains("hello"))
        // Should NOT contain scrollTo since no progression
        #expect(!js.contains("scrollTo"))
    }

    @Test("searchHighlightJS with zero progression does not scroll")
    func noScrollWhenZeroProgression() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "hello", progression: 0.0)
        #expect(!js.isEmpty)
        #expect(!js.contains("scrollTo"))
    }

    @Test("searchHighlightJS with positive progression scrolls before find")
    func scrollsBeforeFind() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "hello", progression: 0.5)
        #expect(!js.isEmpty)
        // Should clear selection, scroll to position, then find
        #expect(js.contains("removeAllRanges"))
        #expect(js.contains("scrollTo"))
    }

    @Test("searchHighlightJS with progression 1.0 scrolls to bottom")
    func scrollsToBottom() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "end text", progression: 1.0)
        #expect(!js.isEmpty)
        #expect(js.contains("scrollTo"))
    }

    @Test("searchHighlightJS with empty text returns empty regardless of progression")
    func emptyTextReturnsEmpty() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "", progression: 0.5)
        #expect(js.isEmpty)
    }

    @Test("searchHighlightJS with whitespace text returns empty regardless of progression")
    func whitespaceTextReturnsEmpty() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "   ", progression: 0.75)
        #expect(js.isEmpty)
    }

    @Test("searchHighlightJS without progression parameter defaults to no scroll")
    func backwardCompatNoParm() {
        // Calling without progression parameter should still work (backward compat)
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "hello")
        #expect(!js.isEmpty)
        #expect(js.contains("hello"))
        #expect(!js.contains("scrollTo"))
    }

    @Test("searchHighlightJS escapes text with progression")
    func escapesWithProgression() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "it's a \"test\"", progression: 0.3)
        #expect(!js.isEmpty)
        #expect(js.contains("\\'"))
    }

    @Test("searchHighlightJS with CJK text and progression")
    func cjkWithProgression() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "你好世界", progression: 0.25)
        #expect(!js.isEmpty)
        #expect(js.contains("你好世界"))
        #expect(js.contains("scrollTo"))
    }
}
#endif
