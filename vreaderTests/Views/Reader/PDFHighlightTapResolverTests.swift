// Purpose: Tests for PDFHighlightTapResolver — Feature #53 WI-6.
// The PDF reader detects a tap on an existing highlight via a UITapGesture
// on PDFView, converts the tap point to page-local coordinates, then walks
// the renderer's `annotationMap` to find which highlight UUID (if any) owns
// the tapped point. This resolver is the pure-function gate — testable
// without a real PDFView or gesture.

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
import PDFKit
@testable import vreader

@Suite("PDFHighlightTapResolver — point → UUID (Feature #53 WI-6)")
struct PDFHighlightTapResolverTests {

    /// Builds a `PDFAnnotation` of type `.highlight` on `page` with the given
    /// bounds. PDFKit annotations are page-bound (the page is stored on the
    /// annotation itself when added via `page.addAnnotation`); this helper
    /// uses `setValue(page, forAnnotationKey: .page)` to set the page
    /// reference without mutating the page's annotation list (we don't need
    /// the page-side state for the resolver test — only the annotation's
    /// `.bounds` and `.page` properties).
    private func makeHighlightAnnotation(bounds: CGRect, page: PDFPage) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        page.addAnnotation(annotation)
        return annotation
    }

    private func makePage() -> PDFPage {
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        return page
    }

    @Test
    func resolve_pointInsideHighlightBounds_returnsHighlightID() {
        let page = makePage()
        let id = UUID()
        let annotation = makeHighlightAnnotation(
            bounds: CGRect(x: 50, y: 100, width: 200, height: 30),
            page: page
        )
        let map: [UUID: [PDFAnnotation]] = [id: [annotation]]
        let resolved = PDFHighlightTapResolver.resolveHighlightID(
            atPagePoint: CGPoint(x: 100, y: 115),
            onPage: page,
            annotationMap: map
        )
        #expect(resolved == id)
    }

    @Test
    func resolve_pointOutsideAllHighlights_returnsNil() {
        let page = makePage()
        let id = UUID()
        let annotation = makeHighlightAnnotation(
            bounds: CGRect(x: 50, y: 100, width: 200, height: 30),
            page: page
        )
        let map: [UUID: [PDFAnnotation]] = [id: [annotation]]
        let resolved = PDFHighlightTapResolver.resolveHighlightID(
            atPagePoint: CGPoint(x: 500, y: 500),
            onPage: page,
            annotationMap: map
        )
        #expect(resolved == nil)
    }

    @Test
    func resolve_pointOnDifferentPage_returnsNil() {
        // Guard: the resolver must check page identity. A highlight on
        // page A whose bounds happen to overlap the tap point on page B
        // must not return.
        let pageA = makePage()
        let pageB = makePage()
        let id = UUID()
        let annotation = makeHighlightAnnotation(
            bounds: CGRect(x: 50, y: 100, width: 200, height: 30),
            page: pageA
        )
        let map: [UUID: [PDFAnnotation]] = [id: [annotation]]
        let resolved = PDFHighlightTapResolver.resolveHighlightID(
            atPagePoint: CGPoint(x: 100, y: 115),
            onPage: pageB,
            annotationMap: map
        )
        #expect(resolved == nil)
    }

    @Test
    func resolve_multiRectHighlight_anyRectContainsPoint() {
        // Edge: a single highlight can span multiple PDFAnnotation objects
        // (one per visual rect for multi-line selections). Any of them
        // containing the point must return the highlight's UUID.
        let page = makePage()
        let id = UUID()
        let line1 = makeHighlightAnnotation(
            bounds: CGRect(x: 50, y: 100, width: 200, height: 20),
            page: page
        )
        let line2 = makeHighlightAnnotation(
            bounds: CGRect(x: 50, y: 130, width: 150, height: 20),
            page: page
        )
        let map: [UUID: [PDFAnnotation]] = [id: [line1, line2]]
        let resolved = PDFHighlightTapResolver.resolveHighlightID(
            atPagePoint: CGPoint(x: 80, y: 140),  // inside line2
            onPage: page,
            annotationMap: map
        )
        #expect(resolved == id)
    }

    @Test
    func resolve_emptyMap_returnsNil() {
        let page = makePage()
        let resolved = PDFHighlightTapResolver.resolveHighlightID(
            atPagePoint: CGPoint(x: 100, y: 100),
            onPage: page,
            annotationMap: [:]
        )
        #expect(resolved == nil)
    }

    @Test
    func resolve_overlappingHighlights_firstFoundWins() {
        // Edge: two highlights whose bounds overlap at the tap point —
        // the resolver returns SOME UUID; order is implementation-defined
        // because dictionary iteration is unordered. Test asserts that
        // the returned UUID is one of the two candidates, not nil.
        let page = makePage()
        let id1 = UUID()
        let id2 = UUID()
        let ann1 = makeHighlightAnnotation(
            bounds: CGRect(x: 50, y: 100, width: 200, height: 30),
            page: page
        )
        let ann2 = makeHighlightAnnotation(
            bounds: CGRect(x: 100, y: 110, width: 100, height: 20),
            page: page
        )
        let map: [UUID: [PDFAnnotation]] = [id1: [ann1], id2: [ann2]]
        let resolved = PDFHighlightTapResolver.resolveHighlightID(
            atPagePoint: CGPoint(x: 120, y: 120),  // in both bounds
            onPage: page,
            annotationMap: map
        )
        #expect(resolved == id1 || resolved == id2,
                "Overlapping highlights must resolve to one of the candidates, not nil")
    }
}
#endif
