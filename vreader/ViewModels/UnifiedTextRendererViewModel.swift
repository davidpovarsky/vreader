// Purpose: ViewModel for the unified reflow engine (WI-B04, WI-B05).
// Manages pagination state, page navigation, and progress tracking
// using TextKit2Paginator for paged mode and UTF-16 offsets for scroll mode.
// Supports both plain text (TXT) and pre-formatted attributed text (MD, EPUB).
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Reuses TextKit2Paginator from F08 spike for page calculation.
// - Scroll mode tracks progress via UTF-16 character offsets.
// - Paged mode tracks progress via currentPage / (totalPages - 1).
// - configure() re-paginates when font, viewport, or layout changes.
// - configureAttributed() preserves NSAttributedString formatting (WI-B05).
// - Mode switching preserves approximate reading progress.
//
// @coordinates-with: TextKit2Paginator.swift, UnifiedTextRenderer.swift,
//   UnifiedPagedView.swift, UnifiedScrollView.swift

import Foundation
import UIKit

/// ViewModel for the Unified TXT Reflow Engine.
@Observable
@MainActor
final class UnifiedTextRendererViewModel {

    // MARK: - Published State

    /// The full text content.
    let text: String

    /// Current page index (0-based). Used in paged mode.
    private(set) var currentPage: Int = 0

    /// Total number of pages. 0 for scroll mode or empty text.
    private(set) var totalPages: Int = 0

    /// Current layout mode.
    private(set) var layout: EPUBLayoutPreference = .scroll

    /// Optional callback invoked whenever reading progress changes (page navigation or scroll).
    var onProgressChange: ((Double) -> Void)?

    /// The full attributed text, if configured via `configureAttributed()`. Nil for plain text.
    private(set) var attributedText: NSAttributedString?

    // MARK: - Private State

    private let paginator = TextKit2Paginator()
    private var totalLengthUTF16: Int = 0
    private var currentScrollOffsetUTF16: Int = 0

    /// Optional pagination cache for avoiding redundant TextKit layout passes (Issue 7).
    private let cache: PaginationCache?
    /// Document fingerprint used as part of the cache key.
    private let documentFingerprint: String

    // MARK: - Computed

    /// Whether the current layout is scroll mode.
    var isScrollMode: Bool { layout == .scroll }

    /// Whether the current layout is paged mode.
    var isPagedMode: Bool { layout == .paged }

    /// The text content of the current page (paged mode only). Nil if no pages.
    var currentPageText: String? {
        guard isPagedMode, currentPage < paginator.pages.count else { return nil }
        return paginator.pages[currentPage].text
    }

    /// The attributed text content of the current page (paged mode, attributed text only).
    /// Returns the attributed substring for the current page's text range, or nil if
    /// plain text mode or no pages.
    var currentPageAttributedText: NSAttributedString? {
        guard isPagedMode,
              currentPage < paginator.pages.count,
              let attrText = attributedText else { return nil }
        let range = paginator.pages[currentPage].textRange
        guard range.location + range.length <= attrText.length else { return nil }
        return attrText.attributedSubstring(from: range)
    }

    /// Reading progress as a fraction in 0.0...1.0.
    var progress: Double {
        if isPagedMode {
            guard totalPages > 1 else { return 0.0 }
            return Double(currentPage) / Double(totalPages - 1)
        } else {
            guard totalLengthUTF16 > 0 else { return 0.0 }
            return Double(currentScrollOffsetUTF16) / Double(totalLengthUTF16)
        }
    }

    // MARK: - Init

    init(text: String, cache: PaginationCache? = nil, documentFingerprint: String = "") {
        self.text = text
        self.totalLengthUTF16 = (text as NSString).length
        self.cache = cache
        self.documentFingerprint = documentFingerprint
    }

    // MARK: - Configuration

    /// Configures (or reconfigures) the renderer with the given font, viewport, and layout.
    /// In paged mode, this triggers re-pagination. Progress is preserved across reconfiguration.
    /// If a PaginationCache was provided, checks it before paginating and stores results after.
    func configure(font: UIFont, viewportSize: CGSize, layout: EPUBLayoutPreference) {
        let previousProgress = self.progress
        self.layout = layout

        if layout == .paged {
            let cacheKey = PaginationCacheKey(
                documentFingerprint: documentFingerprint,
                fontSize: font.pointSize,
                fontName: font.fontName,
                lineSpacing: 0,
                viewportWidth: viewportSize.width,
                viewportHeight: viewportSize.height
            )

            // Issue 7: Check cache before paginating
            if let cached = cache?.get(key: cacheKey) {
                totalPages = cached.count
            } else {
                paginator.paginate(text: text, font: font, viewportSize: viewportSize)
                totalPages = paginator.totalPages

                // Store in cache for future use
                if !documentFingerprint.isEmpty {
                    let cachePages = paginator.pages.enumerated().map { idx, page in
                        PaginationCachePage(
                            pageIndex: idx,
                            charLocation: page.textRange.location,
                            charLength: page.textRange.length
                        )
                    }
                    cache?.set(key: cacheKey, pages: cachePages)
                }
            }

            // Restore approximate page from previous progress
            if totalPages > 1 {
                let targetPage = Int((previousProgress * Double(totalPages - 1)).rounded())
                currentPage = max(0, min(targetPage, totalPages - 1))
            } else {
                currentPage = 0
            }
        } else {
            totalPages = 0
            currentPage = 0
            // Restore scroll offset from previous progress
            currentScrollOffsetUTF16 = Int((previousProgress * Double(totalLengthUTF16)).rounded())
        }
    }

    // MARK: - Configuration (Attributed Text — WI-B05)

    /// Configures (or reconfigures) the renderer with pre-formatted attributed text.
    /// Preserves bold, italic, heading sizes, and other formatting through pagination.
    /// Progress is preserved across reconfiguration.
    ///
    /// - Parameters:
    ///   - attributedText: The attributed text to render. Formatting is preserved per page.
    ///   - viewportSize: The available viewport size for layout.
    ///   - layout: Scroll or paged mode (defaults to `.paged`).
    func configureAttributed(
        attributedText: NSAttributedString,
        viewportSize: CGSize,
        layout: EPUBLayoutPreference = .paged
    ) {
        let previousProgress = self.progress
        self.layout = layout
        self.attributedText = attributedText

        if layout == .paged {
            // Use the font from the attributed string's first character, or system default.
            let fallbackFont = attributedText.length > 0
                ? (attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
                   ?? UIFont.systemFont(ofSize: 17))
                : UIFont.systemFont(ofSize: 17)

            paginator.paginateAttributed(
                attributedText: attributedText,
                font: fallbackFont,
                viewportSize: viewportSize
            )
            totalPages = paginator.totalPages

            if totalPages > 1 {
                let targetPage = Int((previousProgress * Double(totalPages - 1)).rounded())
                currentPage = max(0, min(targetPage, totalPages - 1))
            } else {
                currentPage = 0
            }
        } else {
            totalPages = 0
            currentPage = 0
            currentScrollOffsetUTF16 = Int((previousProgress * Double(totalLengthUTF16)).rounded())
        }
    }

    // MARK: - Navigation (Paged Mode)

    /// Advance to the next page. No-op at last page or in scroll mode.
    func nextPage() {
        guard isPagedMode, totalPages > 0 else { return }
        let target = currentPage + 1
        guard target < totalPages else { return }
        currentPage = target
        onProgressChange?(progress)
    }

    /// Go to the previous page. No-op at first page or in scroll mode.
    func previousPage() {
        guard isPagedMode else { return }
        let target = currentPage - 1
        guard target >= 0 else { return }
        currentPage = target
        onProgressChange?(progress)
    }

    /// Jump to a specific page. Values are clamped to valid range.
    func goToPage(_ page: Int) {
        guard isPagedMode, totalPages > 0 else { return }
        currentPage = max(0, min(page, totalPages - 1))
        onProgressChange?(progress)
    }

    // MARK: - Scroll Position (Scroll Mode)

    /// Update the current scroll position in UTF-16 character offset.
    func updateScrollOffset(charOffsetUTF16: Int) {
        guard totalLengthUTF16 > 0 else { return }
        currentScrollOffsetUTF16 = max(0, min(charOffsetUTF16, totalLengthUTF16))
        onProgressChange?(progress)
    }

    /// Returns the UTF-16 character offset for the given progress fraction.
    func charOffsetForProgress(_ progress: Double) -> Int {
        let clamped = max(0.0, min(progress, 1.0))
        return Int((clamped * Double(totalLengthUTF16)).rounded())
    }
}
