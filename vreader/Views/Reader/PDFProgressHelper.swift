// Purpose: Pure-logic helpers for PDF reading progress bar wiring (WI-004c).
// Converts between page indices and progress values (0.0-1.0),
// generates labels, and determines visibility/discrete steps.
//
// Key decisions:
// - All methods are static for testability (no ViewModel coupling).
// - Single-page documents report progress 1.0 (user has reached the only page).
// - Empty documents (0 pages) return 0.0 progress and nil discrete steps.
// - discreteSteps returns totalPages-1 (the number of intervals) so that
//   snappedValue() produces exactly totalPages snap positions aligned to pages.
// - Seek values are clamped to 0.0-1.0 before page computation.
// - Page labels use 1-based display ("Page X of Y").
//
// @coordinates-with: ReadingProgressBar.swift, PDFReaderContainerView.swift

import Foundation

/// Pure-logic helpers for wiring ReadingProgressBar into the PDF reader.
enum PDFProgressHelper {

    /// Computes reading progress (0.0-1.0) from a zero-based page index.
    /// Returns 1.0 for single-page documents (user is at the only page).
    /// Returns 0.0 for empty documents (totalPages == 0).
    static func progressForPage(currentPageIndex: Int, totalPages: Int) -> Double {
        guard totalPages > 0 else { return 0.0 }
        guard totalPages > 1 else { return 1.0 }
        return Double(currentPageIndex) / Double(totalPages - 1)
    }

    /// Converts a seek value (0.0-1.0) to a zero-based page index.
    /// Clamps the seek value and rounds to the nearest page.
    static func pageForSeekValue(seekValue: Double, totalPages: Int) -> Int {
        guard totalPages > 1 else { return 0 }
        let clamped = min(max(seekValue, 0.0), 1.0)
        let rawPage = (clamped * Double(totalPages - 1)).rounded()
        return Int(rawPage)
    }

    /// Formats a "Page X of Y" label from a zero-based page index.
    /// Returns "Page 0 of 0" for empty documents.
    static func pageLabel(currentPageIndex: Int, totalPages: Int) -> String {
        guard totalPages > 0 else { return "Page 0 of 0" }
        return "Page \(currentPageIndex + 1) of \(totalPages)"
    }

    /// Returns the number of discrete steps for the progress bar slider.
    ///
    /// The progress bar's `snappedValue(_:discreteSteps:)` interprets N steps as
    /// N+1 snap positions (0/N through N/N). PDF progress values live at
    /// `pageIndex / (totalPages - 1)`, so we need `totalPages - 1` intervals
    /// to align snap positions with page boundaries.
    ///
    /// Returns nil for single-page or empty documents (no snapping needed).
    static func discreteSteps(totalPages: Int) -> Int? {
        guard totalPages > 1 else { return nil }
        return totalPages - 1
    }

    /// Whether the progress bar should be visible.
    /// Hidden when document is not loaded or has zero pages.
    static func shouldShowProgressBar(isDocumentLoaded: Bool, totalPages: Int) -> Bool {
        isDocumentLoaded && totalPages > 0
    }
}
