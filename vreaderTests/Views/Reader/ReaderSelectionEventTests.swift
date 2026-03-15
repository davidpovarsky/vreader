// Purpose: Tests for ReaderSelectionEvent — field access, notification name.

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("ReaderSelectionEvent")
struct ReaderSelectionEventTests {

    @Test func selectionEventCarriesAllFields() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 10
        )
        let anchor = AnnotationAnchor.epub(
            href: "ch1.xhtml",
            cfi: "/6/4",
            serializedRange: range
        )
        let rect = CGRect(x: 100, y: 200, width: 150, height: 20)

        let event = ReaderSelectionEvent(
            selectedText: "Hello World",
            anchor: anchor,
            sourceRect: rect
        )

        #expect(event.selectedText == "Hello World")
        #expect(event.anchor == anchor)
        #expect(event.sourceRect == rect)
    }

    @Test func selectionEventWithPDFAnchor() {
        let anchor = AnnotationAnchor.pdf(
            page: 5,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.02)]
        )
        let event = ReaderSelectionEvent(
            selectedText: "PDF selection",
            anchor: anchor,
            sourceRect: CGRect(x: 50, y: 300, width: 200, height: 30)
        )

        #expect(event.selectedText == "PDF selection")
        if case .pdf(let page, let rects) = event.anchor {
            #expect(page == 5)
            #expect(rects.count == 1)
        } else {
            Issue.record("Expected PDF anchor")
        }
    }

    @Test func selectionEventWithTextAnchor() {
        let anchor = AnnotationAnchor.text(
            sourceUnitId: "main-doc",
            startUTF16: 500,
            endUTF16: 600
        )
        let event = ReaderSelectionEvent(
            selectedText: "Some text selection",
            anchor: anchor,
            sourceRect: .zero
        )

        #expect(event.selectedText == "Some text selection")
        if case .text(let unitId, let start, let end) = event.anchor {
            #expect(unitId == "main-doc")
            #expect(start == 500)
            #expect(end == 600)
        } else {
            Issue.record("Expected text anchor")
        }
    }

    @Test func selectionEventWithEmptyText() {
        let anchor = AnnotationAnchor.text(sourceUnitId: "u", startUTF16: 0, endUTF16: 0)
        let event = ReaderSelectionEvent(
            selectedText: "",
            anchor: anchor,
            sourceRect: .zero
        )
        #expect(event.selectedText.isEmpty)
    }

    @Test func selectionEventWithCJKText() {
        let anchor = AnnotationAnchor.text(sourceUnitId: "u", startUTF16: 0, endUTF16: 4)
        let event = ReaderSelectionEvent(
            selectedText: "你好世界",
            anchor: anchor,
            sourceRect: CGRect(x: 10, y: 20, width: 80, height: 20)
        )
        #expect(event.selectedText == "你好世界")
    }

    @Test func notificationNameIsCorrect() {
        #expect(Notification.Name.readerTextSelected.rawValue == "vreader.readerTextSelected")
    }
}
