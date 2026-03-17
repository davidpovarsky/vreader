// Purpose: Adapter that wraps NativeTextPaginator with the PageNavigator protocol.
// Provides page navigation (next/prev/jump), reading position restoration via
// UTF-16 offsets, and text extraction for the current page.
//
// Key decisions:
// - Composes NativeTextPaginator (TextKit 1 layout) + BasePageNavigator (navigation logic).
// - Re-pagination preserves approximate reading position via progression fraction.
// - currentPageText() and currentPageAttributedText() extract content for the active page.
// - pageContainingOffset() maps a UTF-16 offset to a page index for position restore.
//
// @coordinates-with: NativeTextPaginator.swift, BasePageNavigator.swift,
//   PageNavigator.swift, TXTReaderContainerView.swift, MDReaderContainerView.swift

#if canImport(UIKit)
import UIKit

/// Page navigator backed by NativeTextPaginator (TextKit 1).
/// Conforms to PageNavigator for use with AutoPageTurner and tap zone navigation.
@MainActor
final class NativeTextPageNavigator: PageNavigator {

    // MARK: - Backing Components

    private let paginator = NativeTextPaginator()
    private let base = BasePageNavigator()

    // MARK: - PageNavigator Conformance

    var currentPage: Int { base.currentPage }

    var totalPages: Int {
        get { base.totalPages }
        set { base.totalPages = newValue }
    }

    weak var delegate: (any PageNavigatorDelegate)? {
        get { base.delegate }
        set { base.delegate = newValue }
    }

    var progression: Double { base.progression }

    func nextPage() { base.nextPage() }
    func previousPage() { base.previousPage() }
    func jumpToPage(_ page: Int) { base.jumpToPage(page) }

    // MARK: - Pagination

    /// Paginate plain text. Preserves approximate reading position.
    func paginate(text: String, font: UIFont, viewportSize: CGSize) {
        let previousProgression = progression
        paginator.paginate(text: text, font: font, viewportSize: viewportSize)
        base.totalPages = paginator.totalPages
        restorePosition(from: previousProgression)
    }

    /// Paginate attributed text. Preserves approximate reading position.
    func paginateAttributed(attributedText: NSAttributedString, viewportSize: CGSize) {
        let previousProgression = progression
        paginator.paginateAttributed(attributedText: attributedText, viewportSize: viewportSize)
        base.totalPages = paginator.totalPages
        restorePosition(from: previousProgression)
    }

    // MARK: - Page Content

    /// Returns the plain text for the current page, or nil if no pages.
    func currentPageText(from text: String) -> String? {
        guard currentPage < paginator.pages.count else { return nil }
        let range = paginator.pages[currentPage].charRange
        let nsString = text as NSString
        guard range.location + range.length <= nsString.length else { return nil }
        return nsString.substring(with: range)
    }

    /// Returns the attributed text for the current page, or nil if no pages.
    func currentPageAttributedText(from attributedText: NSAttributedString) -> NSAttributedString? {
        guard currentPage < paginator.pages.count else { return nil }
        let range = paginator.pages[currentPage].charRange
        guard range.location + range.length <= attributedText.length else { return nil }
        return attributedText.attributedSubstring(from: range)
    }

    // MARK: - Position Restoration

    /// Returns the page index containing the given UTF-16 offset, or nil.
    func pageContainingOffset(utf16Offset: Int) -> Int? {
        paginator.pageContaining(offsetUTF16: utf16Offset)
    }

    /// Jump to the page containing the given UTF-16 offset.
    /// No-op if offset is out of range.
    func jumpToOffset(utf16Offset: Int) {
        if let page = pageContainingOffset(utf16Offset: utf16Offset) {
            jumpToPage(page)
        }
    }

    /// Returns the UTF-16 character range for the current page, or nil.
    var currentPageCharRange: NSRange? {
        guard currentPage < paginator.pages.count else { return nil }
        return paginator.pages[currentPage].charRange
    }

    // MARK: - Private

    private func restorePosition(from previousProgression: Double) {
        guard totalPages > 1, previousProgression > 0 else { return }
        let targetPage = Int((previousProgression * Double(totalPages - 1)).rounded())
        base.jumpToPage(targetPage)
    }
}
#endif
