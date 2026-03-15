// Purpose: Tests for PDFAnnotationBridge — highlight annotation creation, removal,
// restoration, and rect normalization for PDF documents.
//
// @coordinates-with: PDFAnnotationBridge.swift, AnnotationAnchor.swift, HighlightRecord.swift

#if canImport(UIKit)
import Testing
import Foundation
import PDFKit
import CoreGraphics
@testable import vreader

@Suite("PDFAnnotationBridge")
struct PDFAnnotationBridgeTests {

    // MARK: - Test Helpers

    /// Creates a minimal single-page PDFDocument for testing.
    /// The page has a known mediaBox for predictable coordinate math.
    private func makeSinglePageDocument(
        mediaBox: CGRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    ) -> (PDFDocument, PDFPage) {
        let page = PDFPage()
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        return (doc, page)
    }

    /// Creates a multi-page PDFDocument for testing.
    private func makeMultiPageDocument(pageCount: Int) -> PDFDocument {
        let doc = PDFDocument()
        for i in 0..<pageCount {
            let page = PDFPage()
            doc.insert(page, at: i)
        }
        return doc
    }

    // MARK: - Highlight Creation

    @Test("createHighlight produces PDFAnnotation on page")
    func highlightAnnotationCreated() {
        let (_, page) = makeSinglePageDocument()
        let rects = [CGRect(x: 100, y: 600, width: 200, height: 20)]

        let annotations = PDFAnnotationBridge.createHighlight(
            on: page, rects: rects, color: .yellow
        )

        #expect(annotations.count == 1)
        #expect(page.annotations.count == 1)
        #expect(page.annotations.first === annotations.first)
    }

    @Test("highlight annotation uses correct color")
    func highlightColorMatchesTheme() {
        let (_, page) = makeSinglePageDocument()
        let rects = [CGRect(x: 50, y: 700, width: 150, height: 15)]

        let annotations = PDFAnnotationBridge.createHighlight(
            on: page, rects: rects, color: .yellow
        )

        #expect(annotations.count == 1)
        // PDFAnnotation highlight color should be set
        let annotation = annotations[0]
        #expect(annotation.color != nil)
    }

    @Test("highlight annotation type is .highlight")
    func highlightAnnotationTypeIsHighlight() {
        let (_, page) = makeSinglePageDocument()
        let rects = [CGRect(x: 50, y: 700, width: 150, height: 15)]

        let annotations = PDFAnnotationBridge.createHighlight(
            on: page, rects: rects, color: .yellow
        )

        let annotation = annotations[0]
        #expect(annotation.type == "Highlight")
    }

    // MARK: - Remove Annotation

    @Test("removeHighlight deletes annotation from page")
    func removeAnnotationDeletesFromPage() {
        let (_, page) = makeSinglePageDocument()
        let rects = [CGRect(x: 100, y: 600, width: 200, height: 20)]

        let annotations = PDFAnnotationBridge.createHighlight(
            on: page, rects: rects, color: .yellow
        )
        #expect(page.annotations.count == 1)

        PDFAnnotationBridge.removeHighlight(annotations: annotations, from: page)
        #expect(page.annotations.isEmpty)
    }

    @Test("removeHighlight with empty array is a no-op")
    func removeEmptyAnnotationsIsNoOp() {
        let (_, page) = makeSinglePageDocument()
        // No crash, no change
        PDFAnnotationBridge.removeHighlight(annotations: [], from: page)
        #expect(page.annotations.isEmpty)
    }

    // MARK: - Correct Page

    @Test("annotation is created on the correct page")
    func annotationCreatedForCorrectPage() {
        let doc = makeMultiPageDocument(pageCount: 5)
        let targetPage = doc.page(at: 2)!
        let otherPage = doc.page(at: 0)!
        let rects = [CGRect(x: 50, y: 400, width: 100, height: 10)]

        let annotations = PDFAnnotationBridge.createHighlight(
            on: targetPage, rects: rects, color: .yellow
        )

        #expect(targetPage.annotations.count == 1)
        #expect(otherPage.annotations.isEmpty)
        #expect(annotations.count == 1)
    }

    // MARK: - Multi-line Selection

    @Test("multi-line selection creates multiple annotations")
    func multiLineSelectionCreatesMultipleRects() {
        let (_, page) = makeSinglePageDocument()
        let rects = [
            CGRect(x: 100, y: 700, width: 400, height: 15),
            CGRect(x: 50, y: 680, width: 450, height: 15),
            CGRect(x: 50, y: 660, width: 200, height: 15),
        ]

        let annotations = PDFAnnotationBridge.createHighlight(
            on: page, rects: rects, color: .yellow
        )

        #expect(annotations.count == 3)
        #expect(page.annotations.count == 3)
    }

    // MARK: - Rect Normalization

    @Test("normalizeRects converts page-space rects to 0-1 range")
    func normalizedRectsAreInPageSpace() {
        // Page is 612 x 792 (standard US Letter)
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pageRect = CGRect(x: 100, y: 200, width: 200, height: 20)

        let normalized = PDFAnnotationBridge.normalizeRects(
            [pageRect], pageBounds: pageBounds
        )

        #expect(normalized.count == 1)
        let r = normalized[0]
        // x: 100/612, y: 200/792, w: 200/612, h: 20/792
        #expect(abs(r.origin.x - 100.0 / 612.0) < 0.001)
        #expect(abs(r.origin.y - 200.0 / 792.0) < 0.001)
        #expect(abs(r.width - 200.0 / 612.0) < 0.001)
        #expect(abs(r.height - 20.0 / 792.0) < 0.001)
    }

    @Test("denormalizeRects converts 0-1 rects back to page-space")
    func denormalizedRectsAreInPageSpace() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let normalizedRect = CGRect(
            x: 100.0 / 612.0,
            y: 200.0 / 792.0,
            width: 200.0 / 612.0,
            height: 20.0 / 792.0
        )

        let denormalized = PDFAnnotationBridge.denormalizeRects(
            [normalizedRect], pageBounds: pageBounds
        )

        #expect(denormalized.count == 1)
        let r = denormalized[0]
        #expect(abs(r.origin.x - 100.0) < 0.5)
        #expect(abs(r.origin.y - 200.0) < 0.5)
        #expect(abs(r.width - 200.0) < 0.5)
        #expect(abs(r.height - 20.0) < 0.5)
    }

    @Test("normalize then denormalize is identity (round-trip)")
    func normalizeRoundTrip() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let original = CGRect(x: 150, y: 300, width: 250, height: 18)

        let normalized = PDFAnnotationBridge.normalizeRects([original], pageBounds: pageBounds)
        let recovered = PDFAnnotationBridge.denormalizeRects(normalized, pageBounds: pageBounds)

        #expect(recovered.count == 1)
        let r = recovered[0]
        #expect(abs(r.origin.x - original.origin.x) < 0.5)
        #expect(abs(r.origin.y - original.origin.y) < 0.5)
        #expect(abs(r.width - original.width) < 0.5)
        #expect(abs(r.height - original.height) < 0.5)
    }

    @Test("normalizeRects with empty array returns empty")
    func normalizeEmptyRects() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let normalized = PDFAnnotationBridge.normalizeRects([], pageBounds: pageBounds)
        #expect(normalized.isEmpty)
    }

    @Test("normalizeRects clamps to 0-1 range when rect exceeds page")
    func normalizeClampsToBounds() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        // Rect that extends beyond the page
        let oversizedRect = CGRect(x: -10, y: -5, width: 700, height: 900)

        let normalized = PDFAnnotationBridge.normalizeRects(
            [oversizedRect], pageBounds: pageBounds
        )

        #expect(normalized.count == 1)
        let r = normalized[0]
        // Origin should be clamped to 0
        #expect(r.origin.x >= 0)
        #expect(r.origin.y >= 0)
        // Width + x should not exceed 1
        #expect(r.origin.x + r.width <= 1.001)
        #expect(r.origin.y + r.height <= 1.001)
    }

    @Test("normalizeRects with zero-size page returns empty rects")
    func normalizeZeroSizePageReturnsEmpty() {
        let zeroPage = CGRect(x: 0, y: 0, width: 0, height: 0)
        let rects = [CGRect(x: 10, y: 20, width: 50, height: 10)]
        let normalized = PDFAnnotationBridge.normalizeRects(rects, pageBounds: zeroPage)
        #expect(normalized.isEmpty)
    }

    // MARK: - Empty Rects

    @Test("createHighlight with empty rects returns empty annotations")
    func createHighlightWithEmptyRects() {
        let (_, page) = makeSinglePageDocument()
        let annotations = PDFAnnotationBridge.createHighlight(
            on: page, rects: [], color: .yellow
        )
        #expect(annotations.isEmpty)
        #expect(page.annotations.isEmpty)
    }

    // MARK: - Restore Highlights

    @Test("restoreHighlights creates annotations from HighlightRecords")
    func restoreHighlightsCreatesAnnotations() {
        let doc = makeMultiPageDocument(pageCount: 5)
        let pageBounds = doc.page(at: 2)!.bounds(for: .mediaBox)
        let normalizedRects = [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]

        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makePDFLocator(page: 2),
            anchor: .pdf(page: 2, rects: normalizedRects),
            profileKey: "test",
            selectedText: "Some text",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let result = PDFAnnotationBridge.restoreHighlights(
            for: doc, from: [record]
        )

        #expect(result.count == 1)
        let page = doc.page(at: 2)!
        #expect(page.annotations.count == 1)
    }

    @Test("restoreHighlights skips records without PDF anchor")
    func restoreHighlightsSkipsNonPDFAnchor() {
        let doc = makeMultiPageDocument(pageCount: 3)
        let epubRange = EPUBSerializedRange(
            startContainerPath: "/html/body/p",
            startOffset: 0,
            endContainerPath: "/html/body/p",
            endOffset: 5
        )
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makePDFLocator(page: 0),
            anchor: .epub(href: "ch1.xhtml", cfi: "/6/4", serializedRange: epubRange),
            profileKey: "test",
            selectedText: "Some text",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let result = PDFAnnotationBridge.restoreHighlights(
            for: doc, from: [record]
        )

        #expect(result.isEmpty)
    }

    @Test("restoreHighlights skips records with nil anchor")
    func restoreHighlightsSkipsNilAnchor() {
        let doc = makeMultiPageDocument(pageCount: 3)
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makePDFLocator(page: 0),
            anchor: nil,
            profileKey: "test",
            selectedText: "Some text",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let result = PDFAnnotationBridge.restoreHighlights(
            for: doc, from: [record]
        )

        #expect(result.isEmpty)
    }

    @Test("restoreHighlights skips page index beyond document")
    func restoreHighlightsSkipsBeyondPageCount() {
        let doc = makeMultiPageDocument(pageCount: 3)
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makePDFLocator(page: 10),
            anchor: .pdf(page: 10, rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]),
            profileKey: "test",
            selectedText: "Some text",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let result = PDFAnnotationBridge.restoreHighlights(
            for: doc, from: [record]
        )

        #expect(result.isEmpty)
    }

    @Test("restoreHighlights with empty records array returns empty")
    func restoreHighlightsEmptyRecords() {
        let doc = makeMultiPageDocument(pageCount: 3)

        let result = PDFAnnotationBridge.restoreHighlights(
            for: doc, from: []
        )

        #expect(result.isEmpty)
    }

    @Test("restoreHighlights skips negative page index")
    func restoreHighlightsSkipsNegativePage() {
        let doc = makeMultiPageDocument(pageCount: 3)
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makePDFLocator(page: 0),
            anchor: .pdf(page: -1, rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]),
            profileKey: "test",
            selectedText: "Some text",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let result = PDFAnnotationBridge.restoreHighlights(
            for: doc, from: [record]
        )

        #expect(result.isEmpty)
    }

    // MARK: - Color Mapping

    @Test("colorForName maps yellow string to UIColor.yellow")
    func colorForNameYellow() {
        let color = PDFAnnotationBridge.colorForName("yellow")
        #expect(color == UIColor.yellow.withAlphaComponent(0.3))
    }

    @Test("colorForName maps blue string to blue color")
    func colorForNameBlue() {
        let color = PDFAnnotationBridge.colorForName("blue")
        #expect(color == UIColor.blue.withAlphaComponent(0.3))
    }

    @Test("colorForName maps green string to green color")
    func colorForNameGreen() {
        let color = PDFAnnotationBridge.colorForName("green")
        #expect(color == UIColor.green.withAlphaComponent(0.3))
    }

    @Test("colorForName maps pink string to systemPink color")
    func colorForNamePink() {
        let color = PDFAnnotationBridge.colorForName("pink")
        #expect(color == UIColor.systemPink.withAlphaComponent(0.3))
    }

    @Test("colorForName defaults to yellow for unknown string")
    func colorForNameUnknown() {
        let color = PDFAnnotationBridge.colorForName("magenta")
        #expect(color == UIColor.yellow.withAlphaComponent(0.3))
    }

    @Test("colorForName handles empty string")
    func colorForNameEmpty() {
        let color = PDFAnnotationBridge.colorForName("")
        #expect(color == UIColor.yellow.withAlphaComponent(0.3))
    }

    // MARK: - Selection Event Construction

    @Test("makeSelectionEvent creates event with PDF anchor")
    func selectionEventWithPDFAnchor() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let viewRects = [CGRect(x: 100, y: 200, width: 200, height: 20)]

        let event = PDFAnnotationBridge.makeSelectionEvent(
            selectedText: "Hello World",
            pageIndex: 3,
            viewRects: viewRects,
            pageBounds: pageBounds,
            sourceRect: CGRect(x: 100, y: 200, width: 200, height: 20)
        )

        #expect(event.selectedText == "Hello World")
        if case .pdf(let page, let rects) = event.anchor {
            #expect(page == 3)
            #expect(rects.count == 1)
            // Rects should be normalized
            #expect(rects[0].origin.x >= 0)
            #expect(rects[0].origin.x <= 1)
        } else {
            Issue.record("Expected PDF anchor")
        }
    }

    @Test("makeSelectionEvent with CJK text")
    func selectionEventWithCJKText() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let viewRects = [CGRect(x: 50, y: 300, width: 100, height: 20)]

        let event = PDFAnnotationBridge.makeSelectionEvent(
            selectedText: "你好世界",
            pageIndex: 0,
            viewRects: viewRects,
            pageBounds: pageBounds,
            sourceRect: CGRect(x: 50, y: 300, width: 100, height: 20)
        )

        #expect(event.selectedText == "你好世界")
    }

    @Test("makeSelectionEvent with empty text")
    func selectionEventWithEmptyText() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

        let event = PDFAnnotationBridge.makeSelectionEvent(
            selectedText: "",
            pageIndex: 0,
            viewRects: [],
            pageBounds: pageBounds,
            sourceRect: .zero
        )

        #expect(event.selectedText.isEmpty)
        if case .pdf(_, let rects) = event.anchor {
            #expect(rects.isEmpty)
        } else {
            Issue.record("Expected PDF anchor")
        }
    }

    @Test("makeSelectionEvent preserves sourceRect for popup positioning")
    func selectionEventPreservesSourceRect() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let sourceRect = CGRect(x: 120, y: 450, width: 300, height: 25)

        let event = PDFAnnotationBridge.makeSelectionEvent(
            selectedText: "test",
            pageIndex: 1,
            viewRects: [CGRect(x: 100, y: 200, width: 200, height: 20)],
            pageBounds: pageBounds,
            sourceRect: sourceRect
        )

        #expect(event.sourceRect == sourceRect)
    }

    // MARK: - Multi-rect Normalization

    @Test("normalizeRects handles multiple rects correctly")
    func normalizeMultipleRects() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let rects = [
            CGRect(x: 100, y: 700, width: 400, height: 15),
            CGRect(x: 50, y: 680, width: 450, height: 15),
        ]

        let normalized = PDFAnnotationBridge.normalizeRects(rects, pageBounds: pageBounds)

        #expect(normalized.count == 2)
        // All values should be in 0-1 range
        for r in normalized {
            #expect(r.origin.x >= 0 && r.origin.x <= 1)
            #expect(r.origin.y >= 0 && r.origin.y <= 1)
            #expect(r.width >= 0 && r.width <= 1)
            #expect(r.height >= 0 && r.height <= 1)
        }
    }

    // MARK: - Zero-dimension Rect

    @Test("createHighlight with zero-width rect still creates annotation")
    func createHighlightZeroWidthRect() {
        let (_, page) = makeSinglePageDocument()
        let rects = [CGRect(x: 100, y: 600, width: 0, height: 20)]

        let annotations = PDFAnnotationBridge.createHighlight(
            on: page, rects: rects, color: .yellow
        )

        // Zero-width rects are passed through — PDFKit handles display
        #expect(annotations.count == 1)
    }

    // MARK: - Bug #56: Invalid Rect Guards

    @Test("denormalizeRects filters out rects with NaN values")
    func denormalizeFiltersNaN() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let rects = [
            CGRect(x: CGFloat.nan, y: 0.2, width: 0.5, height: 0.03),
            CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03),
        ]

        let denormalized = PDFAnnotationBridge.denormalizeRects(rects, pageBounds: pageBounds)

        // NaN rect should be filtered out
        #expect(denormalized.count == 1)
        #expect(denormalized[0].origin.x.isFinite)
    }

    @Test("denormalizeRects filters out rects with infinite values")
    func denormalizeFiltersInfinity() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let rects = [
            CGRect(x: 0.1, y: CGFloat.infinity, width: 0.5, height: 0.03),
        ]

        let denormalized = PDFAnnotationBridge.denormalizeRects(rects, pageBounds: pageBounds)

        #expect(denormalized.isEmpty)
    }

    @Test("denormalizeRects filters out rects with negative width")
    func denormalizeFiltersNegativeWidth() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let rects = [
            CGRect(x: 0.1, y: 0.2, width: -0.5, height: 0.03),
        ]

        let denormalized = PDFAnnotationBridge.denormalizeRects(rects, pageBounds: pageBounds)

        #expect(denormalized.isEmpty)
    }

    @Test("denormalizeRects filters out rects with negative height")
    func denormalizeFiltersNegativeHeight() {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let rects = [
            CGRect(x: 0.1, y: 0.2, width: 0.5, height: -0.03),
        ]

        let denormalized = PDFAnnotationBridge.denormalizeRects(rects, pageBounds: pageBounds)

        #expect(denormalized.isEmpty)
    }

    @Test("denormalizeRects with zero-dimension pageBounds returns empty")
    func denormalizeZeroBoundsReturnsEmpty() {
        let zeroBounds = CGRect(x: 0, y: 0, width: 0, height: 0)
        let rects = [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]

        let denormalized = PDFAnnotationBridge.denormalizeRects(rects, pageBounds: zeroBounds)

        #expect(denormalized.isEmpty)
    }

    @Test("createHighlight filters out rects with non-finite bounds")
    func createHighlightFiltersInvalidRects() {
        let (_, page) = makeSinglePageDocument()
        let rects = [
            CGRect(x: CGFloat.nan, y: 600, width: 200, height: 20),
            CGRect(x: 100, y: 600, width: 200, height: 20),
        ]

        let annotations = PDFAnnotationBridge.createHighlight(
            on: page, rects: rects, color: .yellow
        )

        // Only the valid rect should produce an annotation
        #expect(annotations.count == 1)
        #expect(page.annotations.count == 1)
    }

    @Test("createHighlight filters out rects with negative dimensions")
    func createHighlightFiltersNegativeDimensions() {
        let (_, page) = makeSinglePageDocument()
        let rects = [
            CGRect(x: 100, y: 600, width: -200, height: 20),
            CGRect(x: 100, y: 600, width: 200, height: -20),
        ]

        let annotations = PDFAnnotationBridge.createHighlight(
            on: page, rects: rects, color: .yellow
        )

        #expect(annotations.isEmpty)
        #expect(page.annotations.isEmpty)
    }

    @Test("restoreHighlights handles records with NaN rects gracefully")
    func restoreHighlightsHandlesNaNRects() {
        let doc = makeMultiPageDocument(pageCount: 3)
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makePDFLocator(page: 0),
            anchor: .pdf(page: 0, rects: [
                CGRect(x: CGFloat.nan, y: 0.2, width: 0.5, height: 0.03)
            ]),
            profileKey: "test",
            selectedText: "Some text",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let result = PDFAnnotationBridge.restoreHighlights(
            for: doc, from: [record]
        )

        // Should not crash; NaN rects should be filtered out
        #expect(result.isEmpty)
    }

    @Test("restoreHighlights with mixed valid and invalid rects restores valid ones")
    func restoreHighlightsWithMixedRects() {
        let doc = makeMultiPageDocument(pageCount: 3)
        let validId = UUID()
        let invalidId = UUID()
        let records = [
            HighlightRecord(
                highlightId: validId,
                locator: makePDFLocator(page: 0),
                anchor: .pdf(page: 0, rects: [
                    CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)
                ]),
                profileKey: "test",
                selectedText: "Valid",
                color: "yellow",
                note: nil,
                createdAt: Date(),
                updatedAt: Date()
            ),
            HighlightRecord(
                highlightId: invalidId,
                locator: makePDFLocator(page: 0),
                anchor: .pdf(page: 0, rects: [
                    CGRect(x: CGFloat.nan, y: 0.2, width: 0.5, height: 0.03)
                ]),
                profileKey: "test",
                selectedText: "Invalid",
                color: "yellow",
                note: nil,
                createdAt: Date(),
                updatedAt: Date()
            ),
        ]

        let result = PDFAnnotationBridge.restoreHighlights(
            for: doc, from: records
        )

        // Only the valid record should produce annotations
        #expect(result.count == 1)
        #expect(result[validId] != nil)
        #expect(result[invalidId] == nil)
    }

    @Test("createHighlightFromAnchor with NaN rects returns empty")
    func createFromAnchorWithNaNRects() {
        let doc = makeMultiPageDocument(pageCount: 3)
        let anchor = AnnotationAnchor.pdf(
            page: 0,
            rects: [CGRect(x: CGFloat.nan, y: 0.2, width: 0.5, height: 0.03)]
        )

        let annotations = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: "yellow", in: doc
        )

        #expect(annotations.isEmpty)
    }
}
#endif
