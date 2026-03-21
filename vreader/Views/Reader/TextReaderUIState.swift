// Purpose: Shared @Observable UI state for TXT and MD reader containers (Phase R3).
// Eliminates duplicate @State variables between TXTReaderContainerView and
// MDReaderContainerView. Format-specific state (chunks, attributed strings,
// locator factories) remains in each container.
//
// Key decisions:
// - @Observable enables fine-grained SwiftUI tracking without individual @State vars.
// - Conforms to ReaderNotificationHandlerStateProtocol so the notification modifier
//   can mutate state directly (no Binding wiring needed).
// - Pagination helpers (syncPagedState, updatePagination, updateAutoPageTurner)
//   centralise logic that was duplicated identically in both containers.
// - refreshPersistedHighlights loads DB records into persistedHighlightRanges.
//
// @coordinates-with: ReaderNotificationModifier.swift, ReaderNotificationHandlers.swift,
//   TXTReaderContainerView.swift, MDReaderContainerView.swift,
//   NativeTextPageNavigator.swift, AutoPageTurner.swift

#if canImport(UIKit)
import Foundation
import UIKit

@Observable
@MainActor
final class TextReaderUIState: ReaderNotificationHandlerStateProtocol {

    // MARK: - Highlight & Annotation State

    /// Navigation target from search results. Updated via notification.
    var scrollToOffset: Int?
    /// Match highlight range for search navigation.
    var highlightRange: NSRange?
    /// Whether the current highlight is temporary (search nav) or persistent (user-created).
    var highlightIsTemporary: Bool = true
    /// Persisted highlight ranges loaded from DB on file open.
    var persistedHighlightRanges: [NSRange] = []
    /// Pending annotation info for the "Add Note" flow.
    var pendingAnnotationInfo: TextSelectionInfo?
    /// Text input for the annotation note.
    var annotationNoteText: String = ""

    // MARK: - Reading Progress

    /// Current reading progress for the scrubber bar (0.0-1.0).
    var readingProgress: Double = 0

    // MARK: - Paged Mode State (B08, B10, B11)

    /// Page navigator for paged mode. Nil when in scroll mode or large file.
    var pageNavigator: NativeTextPageNavigator?
    /// Tracks the current page for SwiftUI reactivity.
    var pagedCurrentPage: Int = 0
    /// Auto page turner instance (B10). Created when autoPageTurn is enabled.
    var autoPageTurner: AutoPageTurner?

    // MARK: - Pagination Helpers

    /// Syncs the page counter from the navigator for SwiftUI reactivity.
    /// Returns the character offset of the current page (for position persistence), or nil.
    @discardableResult
    func syncPagedState() -> Int? {
        guard let nav = pageNavigator else { return nil }
        pagedCurrentPage = nav.currentPage
        if nav.totalPages > 1 {
            readingProgress = nav.progression
        }
        return nav.currentPageCharRange?.location
    }

    /// Creates or updates the page navigator when entering paged mode.
    /// Pass the rendered attributed string and the initial scroll offset (nil after first paginate).
    func updatePagination(
        isPagedMode: Bool,
        attributedText: NSAttributedString?,
        initialRestoreOffset: Int?,
        autoPageTurnEnabled: Bool,
        autoPageTurnInterval: TimeInterval
    ) {
        guard isPagedMode, let attrStr = attributedText else {
            autoPageTurner?.stop()
            pageNavigator = nil
            return
        }

        let nav = pageNavigator ?? NativeTextPageNavigator()
        nav.paginateAttributed(
            attributedText: attrStr,
            viewportSize: UIScreen.main.bounds.size
        )

        // Restore position from saved offset on first paginate
        if pageNavigator == nil, let offset = initialRestoreOffset {
            nav.jumpToOffset(utf16Offset: offset)
        }

        pageNavigator = nav

        if autoPageTurnEnabled {
            updateAutoPageTurner(
                enabled: true,
                isPagedMode: isPagedMode,
                interval: autoPageTurnInterval
            )
        }
    }

    /// Starts or stops the auto page turner (B10).
    func updateAutoPageTurner(enabled: Bool, isPagedMode: Bool, interval: TimeInterval) {
        guard enabled, isPagedMode, let nav = pageNavigator else {
            autoPageTurner?.stop()
            return
        }

        let turner = autoPageTurner ?? AutoPageTurner()
        turner.interval = interval
        turner.start(navigator: nav)
        autoPageTurner = turner
    }

    // MARK: - Highlight Persistence

    /// Loads persisted highlight ranges from fetched DB records.
    func refreshPersistedHighlights(from records: [HighlightRecord]) {
        persistedHighlightRanges = records.compactMap { record in
            guard let start = record.locator.charRangeStartUTF16,
                  let end = record.locator.charRangeEndUTF16,
                  end > start else { return nil }
            return NSRange(location: start, length: end - start)
        }
    }
}
#endif
