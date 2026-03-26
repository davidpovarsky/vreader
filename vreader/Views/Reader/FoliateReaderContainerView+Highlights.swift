// Purpose: Highlight creation, restoration, and annotation handling
// for FoliateReaderContainerView. Extracted for file size management.
//
// Key decisions:
// - Selection events from Foliate-js carry CFI-based anchors (not XPath).
// - Highlight restoration on overlay-ready deferred to WI-7 (FoliateHighlightRenderer).
// - Annotation show (highlight tap) posts notification for edit sheet.
//
// @coordinates-with: FoliateReaderContainerView.swift, FoliateTypes.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData

extension FoliateReaderContainerView {

    // MARK: - Selection Handling

    /// Called when Foliate-js reports a text selection.
    /// Posts a notification for the highlight action sheet.
    func handleSelection(_ event: FoliateSelectionEvent) {
        pendingSelectionEvent = event
        showHighlightSheet = true
    }

    // MARK: - Overlay Ready

    /// Called when a section's overlay is ready for highlight injection.
    /// Queries saved highlights for this book and generates restore JS.
    /// Actual JS injection deferred to WI-7 (FoliateHighlightRenderer).
    func handleCreateOverlay(sectionIndex: Int) {
        // WI-7: Query highlights from persistence, filter by section,
        // generate readerAPI.addAnnotation() calls.
        // For now, no-op placeholder.
    }

    // MARK: - Annotation Show

    /// Called when the user taps an existing highlight in the reader.
    /// Posts a notification so the annotations panel can show edit options.
    func handleAnnotationShow(cfi: String) {
        guard FoliateNavigationHelper.isValidNavigationTarget(cfi: cfi) else { return }
        // Post notification with the CFI for the annotations panel.
        // The panel will look up the highlight by CFI and show edit/delete options.
        NotificationCenter.default.post(
            name: .readerHighlightRequested,
            object: FoliateSelectionMapper.notificationPayload(
                from: FoliateSelectionEvent(
                    cfi: cfi,
                    text: "",
                    rect: .zero,
                    sectionIndex: 0
                )
            )
        )
    }
}
#endif
