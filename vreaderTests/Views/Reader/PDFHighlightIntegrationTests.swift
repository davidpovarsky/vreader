// Purpose: Tests for PDF highlight annotation visibility integration.
// Validates that PDFAnnotationBridge.createHighlightFromAnchor correctly
// denormalizes rects and creates visible annotations, and that
// restoreHighlights works with various anchor/document combinations.
//
// @coordinates-with: PDFAnnotationBridge.swift, AnnotationAnchor.swift,
//   PDFReaderContainerView.swift, ReaderNotifications.swift

#if canImport(UIKit)
import Testing
import Foundation
import PDFKit
import CoreGraphics
@testable import vreader

@Suite("PDF Highlight Visibility")
struct PDFHighlightIntegrationTests {

    // MARK: - Test Helpers

    /// Creates a multi-page PDFDocument for testing.
    private func makeDocument(pageCount: Int = 5) -> PDFDocument {
        let doc = PDFDocument()
        for i in 0..<pageCount {
            let page = PDFPage()
            doc.insert(page, at: i)
        }
        return doc
    }

    // MARK: - createHighlightFromAnchor

    @Test("createHighlightFromAnchor creates annotations for valid PDF anchor")
    func createFromAnchorValidPDF() {
        let doc = makeDocument()
        let anchor = AnnotationAnchor.pdf(
            page: 2,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]
        )

        let annotations = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: "yellow", in: doc
        )

        #expect(annotations.count == 1)
        let page = doc.page(at: 2)!
        #expect(page.annotations.count == 1)
        #expect(page.annotations[0].type == "Highlight")
    }

    @Test("createHighlightFromAnchor returns empty for non-PDF anchor")
    func createFromAnchorNonPDF() {
        let doc = makeDocument()
        let epubRange = EPUBSerializedRange(
            startContainerPath: "/html/body/p",
            startOffset: 0,
            endContainerPath: "/html/body/p",
            endOffset: 5
        )
        let anchor = AnnotationAnchor.epub(
            href: "ch1.xhtml", cfi: "/6/4", serializedRange: epubRange
        )

        let annotations = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: "yellow", in: doc
        )

        #expect(annotations.isEmpty)
        for i in 0..<doc.pageCount {
            #expect(doc.page(at: i)!.annotations.isEmpty)
        }
    }

    @Test("createHighlightFromAnchor returns empty for text anchor")
    func createFromAnchorText() {
        let doc = makeDocument()
        let anchor = AnnotationAnchor.text(
            sourceUnitId: "unit1", startUTF16: 10, endUTF16: 50
        )

        let annotations = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: "yellow", in: doc
        )

        #expect(annotations.isEmpty)
    }

    @Test("createHighlightFromAnchor returns empty for page index out of range")
    func createFromAnchorOutOfRange() {
        let doc = makeDocument(pageCount: 3)
        let anchor = AnnotationAnchor.pdf(
            page: 10,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]
        )

        let annotations = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: "yellow", in: doc
        )

        #expect(annotations.isEmpty)
    }

    @Test("createHighlightFromAnchor returns empty for negative page index")
    func createFromAnchorNegativePage() {
        let doc = makeDocument(pageCount: 3)
        let anchor = AnnotationAnchor.pdf(
            page: -1,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]
        )

        let annotations = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: "yellow", in: doc
        )

        #expect(annotations.isEmpty)
    }

    @Test("createHighlightFromAnchor returns empty for empty rects")
    func createFromAnchorEmptyRects() {
        let doc = makeDocument()
        let anchor = AnnotationAnchor.pdf(page: 0, rects: [])

        let annotations = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: "yellow", in: doc
        )

        #expect(annotations.isEmpty)
        #expect(doc.page(at: 0)!.annotations.isEmpty)
    }

    @Test("createHighlightFromAnchor applies correct color")
    func createFromAnchorCorrectColor() {
        let doc = makeDocument()
        let anchor = AnnotationAnchor.pdf(
            page: 0,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]
        )

        let annotations = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: "blue", in: doc
        )

        #expect(annotations.count == 1)
        #expect(annotations[0].color == UIColor.blue.withAlphaComponent(0.3))
    }

    @Test("createHighlightFromAnchor creates multiple annotations for multi-line selection")
    func createFromAnchorMultiLine() {
        let doc = makeDocument()
        let anchor = AnnotationAnchor.pdf(
            page: 0,
            rects: [
                CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.02),
                CGRect(x: 0.05, y: 0.76, width: 0.85, height: 0.02),
                CGRect(x: 0.05, y: 0.72, width: 0.4, height: 0.02),
            ]
        )

        let annotations = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: "green", in: doc
        )

        #expect(annotations.count == 3)
        #expect(doc.page(at: 0)!.annotations.count == 3)
    }

    @Test("createHighlightFromAnchor annotation on correct page only")
    func createFromAnchorCorrectPage() {
        let doc = makeDocument(pageCount: 5)
        let anchor = AnnotationAnchor.pdf(
            page: 3,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]
        )

        _ = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: "yellow", in: doc
        )

        #expect(doc.page(at: 3)!.annotations.count == 1)
        #expect(doc.page(at: 0)!.annotations.isEmpty)
        #expect(doc.page(at: 1)!.annotations.isEmpty)
        #expect(doc.page(at: 2)!.annotations.isEmpty)
        #expect(doc.page(at: 4)!.annotations.isEmpty)
    }

    @Test("createHighlightFromAnchor with unknown color defaults to yellow")
    func createFromAnchorUnknownColor() {
        let doc = makeDocument()
        let anchor = AnnotationAnchor.pdf(
            page: 0,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]
        )

        let annotations = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: "magenta", in: doc
        )

        #expect(annotations.count == 1)
        #expect(annotations[0].color == UIColor.yellow.withAlphaComponent(0.3))
    }

    // MARK: - PDFHighlightNotificationPayload

    @Test("PDFHighlightNotificationPayload stores anchor and color")
    func notificationPayloadStoresData() {
        let anchor = AnnotationAnchor.pdf(
            page: 1,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.04)]
        )
        let payload = PDFHighlightNotificationPayload(anchor: anchor, color: "pink")

        #expect(payload.color == "pink")
        if case .pdf(let page, let rects) = payload.anchor {
            #expect(page == 1)
            #expect(rects.count == 1)
        } else {
            Issue.record("Expected PDF anchor in payload")
        }
    }

    // MARK: - Restore + Create Round-trip

    @Test("restoreHighlights then createHighlightFromAnchor adds to same page")
    func restoreThenCreateAddsToSamePage() {
        let doc = makeDocument(pageCount: 3)

        // Restore one highlight
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makePDFLocator(page: 1),
            anchor: .pdf(page: 1, rects: [CGRect(x: 0.1, y: 0.3, width: 0.4, height: 0.02)]),
            profileKey: "test",
            selectedText: "Existing",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        _ = PDFAnnotationBridge.restoreHighlights(for: doc, from: [record])
        #expect(doc.page(at: 1)!.annotations.count == 1)

        // Create another highlight on the same page
        let anchor = AnnotationAnchor.pdf(
            page: 1,
            rects: [CGRect(x: 0.5, y: 0.6, width: 0.3, height: 0.02)]
        )
        _ = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: "blue", in: doc
        )

        // Both should be on page 1
        #expect(doc.page(at: 1)!.annotations.count == 2)
    }
}
#endif
