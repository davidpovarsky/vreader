// Purpose: Resolves a PDF tap location to the highlight UUID whose annotation
// contains that point. Feature #53 WI-6.
//
// PDFKit has no direct "annotation at point" API beyond `page.annotation(at:)`
// (which returns annotations of any type, including text fields and links).
// Walking the renderer's `annotationMap: [UUID: [PDFAnnotation]]` lets us
// answer the highlight-specific question and recover the UUID in one pass,
// which is what `.readerHighlightTapped`'s payload needs.
//
// Pure-function design so unit tests don't need a real PDFView gesture.
//
// @coordinates-with: PDFViewBridge.swift (gesture caller),
//   PDFHighlightRenderer.swift (annotationMap source),
//   ReaderNotifications.swift, AnnotationAnchor.swift

#if canImport(UIKit)
import Foundation
import CoreGraphics
import PDFKit

enum PDFHighlightTapResolver {
    /// Returns the UUID of the highlight whose annotation rect on `page`
    /// contains `point`, or `nil` if no highlight is hit.
    ///
    /// A highlight may comprise multiple `PDFAnnotation` objects (one per
    /// visual rect for multi-line selections); any of them containing the
    /// point counts as a hit. The first matching UUID wins — for
    /// overlapping highlights, dictionary iteration order is unspecified,
    /// so the caller should design UX around "tap one, get one" rather
    /// than relying on a specific tiebreak.
    static func resolveHighlightID(
        atPagePoint point: CGPoint,
        onPage page: PDFPage,
        annotationMap: [UUID: [PDFAnnotation]]
    ) -> UUID? {
        for (id, annotations) in annotationMap {
            for annotation in annotations {
                guard annotation.page === page else { continue }
                if annotation.bounds.contains(point) {
                    return id
                }
            }
        }
        return nil
    }
}
#endif
