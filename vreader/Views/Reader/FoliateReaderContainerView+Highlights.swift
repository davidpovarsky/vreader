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
import OSLog

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
    /// Feature #53 WI-5: resolve the tapped CFI to its persisted UUID, then
    /// post the cross-format `.readerHighlightTapped` notification so the
    /// inline edit/delete menu surface (used by TXT/MD/EPUB already) can
    /// open. Previously this posted `.readerHighlightRequested` with a
    /// synthetic selection-event payload — that notification fires only
    /// for the create-from-selection path and was silently no-op'd by the
    /// create-path validator, so tapping an existing Foliate highlight
    /// did nothing.
    ///
    /// `sourceRect` is `.zero` for now because the foliate-host.js bridge
    /// doesn't yet forward the annotation's screen-rect — Feature #53 WI-5
    /// scope is the regression fix + resolver. Rect threading + inline
    /// menu presenter wiring follow in a future iteration; the
    /// `.readerHighlightTapped` notification fires today, so any observer
    /// (annotations panel, future presenter) can react.
    func handleAnnotationShow(cfi: String) {
        guard FoliateNavigationHelper.isValidNavigationTarget(cfi: cfi),
              let container = modelContainer else { return }
        let bookKey = viewModel.bookFingerprintKey
        let persistence = PersistenceActor(modelContainer: container)
        Task { @MainActor in
            do {
                let records = try await persistence.fetchHighlights(forBookWithKey: bookKey)
                guard let highlightID = FoliateHighlightTapResolver.resolveHighlightID(
                    forCFI: cfi, in: records
                ) else { return }
                let event = ReaderHighlightTapEvent(
                    highlightID: highlightID,
                    sourceRect: .zero
                )
                NotificationCenter.default.post(
                    name: .readerHighlightTapped, object: event
                )
            } catch {
                // Surfacing the error to the user would be noisy and
                // typically not actionable; logged so a real persistence
                // failure remains diagnosable. Distinct from "resolved
                // nil" (which is a normal not-found, no log).
                let log = Logger(subsystem: "com.vreader.app", category: "FoliateReaderContainerView")
                log.error("annotation-tap resolver fetch failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
#endif
