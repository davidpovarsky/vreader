// Purpose: PDF-specific page navigator wrapping PDFKit's PDFView page navigation.
// Subclasses BasePageNavigator to inherit boundary clamping and delegate notification.
// Syncs with PDFView via syncCurrentPage(_:) called from PDFViewPageChanged notification.
//
// Key decisions:
// - Does NOT hold a reference to PDFView — navigation is handled by the caller
//   (PDFReaderContainerView) which calls the navigator and then tells the bridge to move.
//   This avoids tight coupling and allows pure unit testing without PDFKit.
// - syncCurrentPage(_:) is the inverse path: called when PDFView reports a page change
//   (e.g., user scrolled) so the navigator stays in sync.
// - nextPage/previousPage/jumpToPage are inherited from BasePageNavigator unchanged.
// - The container observes .readerNextPage/.readerPreviousPage notifications and calls
//   the navigator, then uses the resulting currentPage to tell the bridge where to go.
//
// @coordinates-with BasePageNavigator.swift, PDFReaderContainerView.swift,
//   PDFViewBridge.swift, ReaderNotifications.swift

import Foundation

/// PDF-specific page navigator. Wraps BasePageNavigator with a sync method
/// for PDFView page change notifications.
@MainActor
final class PDFPageNavigator: BasePageNavigator {

    /// Synchronizes the navigator's currentPage with the page index reported
    /// by PDFView (via PDFViewPageChanged notification). Clamps the value and
    /// notifies the delegate only if the page actually changed.
    ///
    /// This is the "PDFView told us the page changed" path, as opposed to
    /// nextPage/previousPage/jumpToPage which are the "user tapped a zone" path.
    func syncCurrentPage(_ pageIndex: Int) {
        let maxPage = max(totalPages - 1, 0)
        let clamped = max(0, min(pageIndex, maxPage))
        guard clamped != currentPage else { return }
        jumpToPage(clamped)
    }
}
