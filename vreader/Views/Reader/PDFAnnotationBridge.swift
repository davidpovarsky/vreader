// Purpose: Manages PDFAnnotation creation, removal, and restoration for PDF highlights.
// Handles rect normalization between page coordinate space (0-1) and display space.
// Pure logic — no PDFView dependency, fully unit-testable.
//
// Key decisions:
// - Static methods on an enum (no instances needed).
// - Normalized rects use 0-1 range relative to page bounds for zoom-independent storage.
// - Annotations stored in SwiftData, NOT written into the PDF file (non-destructive).
// - Color mapping from string names to UIColor with alpha for translucent highlights.
//
// @coordinates-with: PDFViewBridge.swift, PDFReaderContainerView.swift,
//   AnnotationAnchor.swift, HighlightRecord.swift, ReaderNotifications.swift

#if canImport(UIKit)
import Foundation
import PDFKit
import CoreGraphics
import UIKit

/// Bridge for PDF highlight annotation operations.
/// All methods are static and pure — no PDFView dependency.
enum PDFAnnotationBridge {

    // MARK: - Highlight Creation

    /// Creates PDFAnnotation highlights on a page, one per rect.
    /// Returns the created annotations (already added to the page).
    @discardableResult
    static func createHighlight(
        on page: PDFPage,
        rects: [CGRect],
        color: UIColor
    ) -> [PDFAnnotation] {
        guard !rects.isEmpty else { return [] }

        var annotations: [PDFAnnotation] = []
        for rect in rects {
            let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            annotation.color = color
            page.addAnnotation(annotation)
            annotations.append(annotation)
        }
        return annotations
    }

    // MARK: - Highlight Removal

    /// Removes the given annotations from the page.
    static func removeHighlight(annotations: [PDFAnnotation], from page: PDFPage) {
        for annotation in annotations {
            page.removeAnnotation(annotation)
        }
    }

    // MARK: - Rect Normalization

    /// Normalizes page-space rects to 0-1 range relative to page bounds.
    /// Returns empty array if page bounds have zero dimensions.
    static func normalizeRects(_ rects: [CGRect], pageBounds: CGRect) -> [CGRect] {
        guard pageBounds.width > 0, pageBounds.height > 0 else { return [] }

        return rects.map { rect in
            let x = max(0, min(1, (rect.origin.x - pageBounds.origin.x) / pageBounds.width))
            let y = max(0, min(1, (rect.origin.y - pageBounds.origin.y) / pageBounds.height))
            let w = max(0, min(1 - x, rect.width / pageBounds.width))
            let h = max(0, min(1 - y, rect.height / pageBounds.height))
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }

    /// Denormalizes 0-1 rects back to page-space using page bounds.
    static func denormalizeRects(_ rects: [CGRect], pageBounds: CGRect) -> [CGRect] {
        return rects.map { rect in
            let x = pageBounds.origin.x + rect.origin.x * pageBounds.width
            let y = pageBounds.origin.y + rect.origin.y * pageBounds.height
            let w = rect.width * pageBounds.width
            let h = rect.height * pageBounds.height
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }

    // MARK: - Color Mapping

    /// Maps a color name string to a translucent UIColor for highlight annotations.
    /// Defaults to yellow if the name is unrecognized.
    static func colorForName(_ name: String) -> UIColor {
        switch name.lowercased() {
        case "yellow":
            return UIColor.yellow.withAlphaComponent(0.3)
        case "blue":
            return UIColor.blue.withAlphaComponent(0.3)
        case "green":
            return UIColor.green.withAlphaComponent(0.3)
        case "pink":
            return UIColor.systemPink.withAlphaComponent(0.3)
        case "orange":
            return UIColor.orange.withAlphaComponent(0.3)
        case "purple":
            return UIColor.purple.withAlphaComponent(0.3)
        default:
            return UIColor.yellow.withAlphaComponent(0.3)
        }
    }

    // MARK: - Selection Event Construction

    /// Creates a ReaderSelectionEvent with a `.pdf` anchor containing normalized rects.
    static func makeSelectionEvent(
        selectedText: String,
        pageIndex: Int,
        viewRects: [CGRect],
        pageBounds: CGRect,
        sourceRect: CGRect
    ) -> ReaderSelectionEvent {
        let normalizedRects = normalizeRects(viewRects, pageBounds: pageBounds)
        let anchor = AnnotationAnchor.pdf(page: pageIndex, rects: normalizedRects)
        return ReaderSelectionEvent(
            selectedText: selectedText,
            anchor: anchor,
            sourceRect: sourceRect
        )
    }

    // MARK: - Anchor-based Highlight Creation

    /// Creates highlight annotations from an AnnotationAnchor on a PDFDocument.
    /// Handles denormalization of rects from the anchor's 0-1 range to page-space.
    /// Returns empty array if the anchor is not a `.pdf` type, the page index is invalid,
    /// or the rects array is empty.
    @discardableResult
    static func createHighlightFromAnchor(
        _ anchor: AnnotationAnchor,
        color: String,
        in document: PDFDocument
    ) -> [PDFAnnotation] {
        guard case .pdf(let pageIndex, let normalizedRects) = anchor,
              pageIndex >= 0,
              pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            return []
        }

        let pageBounds = page.bounds(for: .mediaBox)
        let displayRects = denormalizeRects(normalizedRects, pageBounds: pageBounds)
        let uiColor = colorForName(color)
        return createHighlight(on: page, rects: displayRects, color: uiColor)
    }

    // MARK: - Highlight Restoration

    /// Restores highlight annotations on a PDFDocument from saved HighlightRecords.
    /// Only processes records with a `.pdf` anchor whose page index is valid.
    /// Returns a dictionary mapping highlight IDs to their created annotations.
    @discardableResult
    static func restoreHighlights(
        for document: PDFDocument,
        from records: [HighlightRecord]
    ) -> [UUID: [PDFAnnotation]] {
        var result: [UUID: [PDFAnnotation]] = [:]

        for record in records {
            guard let anchor = record.anchor,
                  case .pdf(let pageIndex, let normalizedRects) = anchor,
                  pageIndex >= 0,
                  pageIndex < document.pageCount,
                  let page = document.page(at: pageIndex) else {
                continue
            }

            let pageBounds = page.bounds(for: .mediaBox)
            let displayRects = denormalizeRects(normalizedRects, pageBounds: pageBounds)
            let color = colorForName(record.color)
            let annotations = createHighlight(on: page, rects: displayRects, color: color)
            if !annotations.isEmpty {
                result[record.highlightId] = annotations
            }
        }

        return result
    }
}
#endif
