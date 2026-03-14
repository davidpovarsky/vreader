// Purpose: Tests for EPUBHighlightBridge — JS message parsing, JS generation,
// notification posting, and edge cases.
//
// @coordinates-with: EPUBHighlightBridge.swift, AnnotationAnchor.swift,
//   ReaderNotifications.swift

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("EPUBHighlightBridge")
struct EPUBHighlightBridgeTests {

    // MARK: - Selection Message Parsing

    @Test("parses selection message with all fields")
    func selectionMessageParsesCorrectly() {
        let body: [String: Any] = [
            "selectedText": "Hello World",
            "startPath": "/html/body/p[1]/text()",
            "startOffset": 5,
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 16,
            "rectX": 100.0,
            "rectY": 200.0,
            "rectWidth": 150.0,
            "rectHeight": 20.0
        ]

        let result = EPUBHighlightBridge.parseSelectionMessage(body)
        #expect(result != nil)
        let parsed = result!
        #expect(parsed.selectedText == "Hello World")
        #expect(parsed.range.startContainerPath == "/html/body/p[1]/text()")
        #expect(parsed.range.startOffset == 5)
        #expect(parsed.range.endContainerPath == "/html/body/p[1]/text()")
        #expect(parsed.range.endOffset == 16)
        #expect(parsed.sourceRect.origin.x == 100.0)
        #expect(parsed.sourceRect.origin.y == 200.0)
        #expect(parsed.sourceRect.size.width == 150.0)
        #expect(parsed.sourceRect.size.height == 20.0)
    }

    @Test("parses selection message with CJK text")
    func selectionMessageWithCJKText() {
        let body: [String: Any] = [
            "selectedText": "你好世界",
            "startPath": "/html/body/div[@class='中文']/p[1]/text()",
            "startOffset": 0,
            "endPath": "/html/body/div[@class='中文']/p[1]/text()",
            "endOffset": 4,
            "rectX": 10.0, "rectY": 20.0, "rectWidth": 80.0, "rectHeight": 20.0
        ]

        let result = EPUBHighlightBridge.parseSelectionMessage(body)
        #expect(result != nil)
        #expect(result!.selectedText == "你好世界")
        #expect(result!.range.startContainerPath == "/html/body/div[@class='中文']/p[1]/text()")
    }

    @Test("returns nil for missing selectedText")
    func selectionMessageMissingText() {
        let body: [String: Any] = [
            "startPath": "/html/body/p[1]/text()",
            "startOffset": 0,
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 5,
            "rectX": 0.0, "rectY": 0.0, "rectWidth": 0.0, "rectHeight": 0.0
        ]
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    @Test("returns nil for missing startPath")
    func selectionMessageMissingStartPath() {
        let body: [String: Any] = [
            "selectedText": "Hello",
            "startOffset": 0,
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 5,
            "rectX": 0.0, "rectY": 0.0, "rectWidth": 0.0, "rectHeight": 0.0
        ]
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    @Test("returns nil for missing endPath")
    func selectionMessageMissingEndPath() {
        let body: [String: Any] = [
            "selectedText": "Hello",
            "startPath": "/html/body/p[1]/text()",
            "startOffset": 0,
            "endOffset": 5,
            "rectX": 0.0, "rectY": 0.0, "rectWidth": 0.0, "rectHeight": 0.0
        ]
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    @Test("returns nil for non-dictionary body")
    func selectionMessageNonDictionary() {
        let body = "not a dictionary"
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    @Test("returns nil for non-integer offsets")
    func selectionMessageNonIntegerOffsets() {
        let body: [String: Any] = [
            "selectedText": "Hello",
            "startPath": "/html/body/p[1]/text()",
            "startOffset": "not a number",
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 5,
            "rectX": 0.0, "rectY": 0.0, "rectWidth": 0.0, "rectHeight": 0.0
        ]
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    @Test("defaults rect to zero when rect fields missing")
    func selectionMessageMissingRectDefaultsToZero() {
        let body: [String: Any] = [
            "selectedText": "Hello",
            "startPath": "/html/body/p[1]/text()",
            "startOffset": 0,
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 5
        ]
        let result = EPUBHighlightBridge.parseSelectionMessage(body)
        #expect(result != nil)
        #expect(result!.sourceRect == .zero)
    }

    // MARK: - Empty Selection Filtering

    @Test("empty selectedText returns nil")
    func emptySelectionIgnored() {
        let body: [String: Any] = [
            "selectedText": "",
            "startPath": "/html/body/p[1]/text()",
            "startOffset": 0,
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 0,
            "rectX": 0.0, "rectY": 0.0, "rectWidth": 0.0, "rectHeight": 0.0
        ]
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    @Test("whitespace-only selectedText returns nil")
    func whitespaceOnlySelectionIgnored() {
        let body: [String: Any] = [
            "selectedText": "   \n\t  ",
            "startPath": "/html/body/p[1]/text()",
            "startOffset": 0,
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 5,
            "rectX": 0.0, "rectY": 0.0, "rectWidth": 0.0, "rectHeight": 0.0
        ]
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    // MARK: - Anchor Construction

    @Test("makeAnchor creates epub anchor with correct fields")
    func makeAnchorCreatesEPUBAnchor() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 5,
            endContainerPath: "/html/body/p[2]/text()",
            endOffset: 10
        )
        let anchor = EPUBHighlightBridge.makeAnchor(
            href: "chapter1.xhtml",
            cfi: "/6/4",
            range: range
        )
        if case .epub(let href, let cfi, let serializedRange) = anchor {
            #expect(href == "chapter1.xhtml")
            #expect(cfi == "/6/4")
            #expect(serializedRange == range)
        } else {
            Issue.record("Expected epub anchor")
        }
    }

    @Test("makeAnchor with empty cfi")
    func makeAnchorWithEmptyCFI() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 5
        )
        let anchor = EPUBHighlightBridge.makeAnchor(href: "ch.xhtml", cfi: "", range: range)
        if case .epub(_, let cfi, _) = anchor {
            #expect(cfi == "")
        } else {
            Issue.record("Expected epub anchor")
        }
    }

    // MARK: - Highlight Injection JS

    @Test("createHighlightJS produces valid JavaScript")
    func highlightInjectionProducesValidJS() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 5,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 16
        )
        let js = EPUBHighlightBridge.createHighlightJS(
            id: "highlight-123",
            range: range,
            color: "yellow"
        )
        #expect(js.contains("highlight-123"))
        #expect(js.contains("yellow"))
        #expect(js.contains("/html/body/p[1]/text()"))
        #expect(js.contains("5"))
        #expect(js.contains("16"))
        #expect(js.contains("createHighlight"))
    }

    @Test("createHighlightJS escapes special characters in ID")
    func highlightJSEscapesSpecialCharsInID() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 5
        )
        let js = EPUBHighlightBridge.createHighlightJS(
            id: "id-with'quotes\"and\\backslash",
            range: range,
            color: "blue"
        )
        // Should not contain unescaped quotes that would break JS
        #expect(!js.contains("'quotes\""))
        #expect(js.contains("createHighlight"))
    }

    @Test("createHighlightJS with CJK XPath")
    func highlightJSWithCJKXPath() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/div[@class='中文']/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/div[@class='中文']/p[1]/text()",
            endOffset: 4
        )
        let js = EPUBHighlightBridge.createHighlightJS(
            id: "cjk-hl",
            range: range,
            color: "yellow"
        )
        #expect(js.contains("createHighlight"))
    }

    // MARK: - Remove Highlight JS

    @Test("removeHighlightJS produces valid script")
    func removeHighlightJSIsValid() {
        let js = EPUBHighlightBridge.removeHighlightJS(id: "highlight-456")
        #expect(js.contains("highlight-456"))
        #expect(js.contains("removeHighlight"))
    }

    @Test("removeHighlightJS escapes special characters")
    func removeHighlightJSEscapesSpecialChars() {
        let js = EPUBHighlightBridge.removeHighlightJS(id: "id'with\"quotes")
        #expect(js.contains("removeHighlight"))
        // Verify no unescaped quotes that would break JS
        #expect(!js.contains("'with\""))
    }

    // MARK: - Restore Highlights JS

    @Test("restoreHighlightsJS produces valid script for multiple highlights")
    func highlightRestoreJSProducesValidScript() {
        let range1 = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 10
        )
        let range2 = EPUBSerializedRange(
            startContainerPath: "/html/body/p[2]/text()",
            startOffset: 5,
            endContainerPath: "/html/body/p[2]/text()",
            endOffset: 20
        )

        let highlights: [(id: String, range: EPUBSerializedRange, color: String)] = [
            ("hl-1", range1, "yellow"),
            ("hl-2", range2, "blue")
        ]

        let js = EPUBHighlightBridge.restoreHighlightsJS(highlights: highlights)
        #expect(js.contains("hl-1"))
        #expect(js.contains("hl-2"))
        #expect(js.contains("yellow"))
        #expect(js.contains("blue"))
        #expect(js.contains("createHighlight"))
    }

    @Test("restoreHighlightsJS with empty array produces no-op")
    func highlightRestoreJSEmptyArray() {
        let js = EPUBHighlightBridge.restoreHighlightsJS(highlights: [])
        // Should be empty or a minimal no-op, not crash
        #expect(js.isEmpty || js.contains("(function"))
    }

    // MARK: - Clear All Highlights JS

    @Test("clearAllHighlightsJS produces valid script")
    func clearAllHighlightsJSIsValid() {
        let js = EPUBHighlightBridge.clearAllHighlightsJS
        #expect(js.contains("clearAllHighlights") || js.contains("CSS.highlights"))
    }

    // MARK: - Selection Event Construction

    @Test("makeSelectionEvent creates event with correct fields")
    func selectionEventConstructedCorrectly() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 10
        )
        let event = EPUBHighlightBridge.makeSelectionEvent(
            selectedText: "Hello World",
            href: "chapter1.xhtml",
            cfi: "/6/4",
            range: range,
            sourceRect: CGRect(x: 100, y: 200, width: 150, height: 20)
        )
        #expect(event.selectedText == "Hello World")
        if case .epub(let href, let cfi, let serializedRange) = event.anchor {
            #expect(href == "chapter1.xhtml")
            #expect(cfi == "/6/4")
            #expect(serializedRange == range)
        } else {
            Issue.record("Expected epub anchor")
        }
        #expect(event.sourceRect.origin.x == 100)
    }

    // MARK: - JS Source Validation

    @Test("selection tracking JS is non-empty and valid")
    func selectionTrackingJSIsValid() {
        let js = EPUBHighlightBridge.selectionTrackingJS
        #expect(!js.isEmpty)
        #expect(js.contains("selectionchange") || js.contains("selectionChanged"))
        #expect(js.contains("webkit.messageHandlers"))
    }

    @Test("highlight API JS is non-empty and contains key functions")
    func highlightAPIJSIsValid() {
        let js = EPUBHighlightBridge.highlightAPIJS
        #expect(!js.isEmpty)
        #expect(js.contains("createHighlight"))
        #expect(js.contains("removeHighlight"))
        #expect(js.contains("clearAllHighlights"))
    }
}
#endif
