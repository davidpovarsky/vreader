// Purpose: TextKit 1 paginator that divides plain or attributed text into
// viewport-sized pages using NSLayoutManager + multiple NSTextContainers.
// Each text container represents one page of the specified viewport size.
//
// Key decisions:
// - @MainActor because TextKit layout managers require main-thread access.
// - Pages use NSRange (UTF-16) to match UIKit/NSString conventions.
// - Empty text produces zero pages.
// - Re-pagination is supported: calling paginate() again replaces prior results.
// - Uses TextKit 1 (NSLayoutManager) to match existing TXT/MD UITextView infra.
// - Standalone paginator — not embedded in UITextView.
// - Two entry points: plain text (font param) and attributed string (MD renderer).
//
// @coordinates-with: NativeTextPaginatorTests.swift, TXTTextViewBridge.swift,
//   BasePageNavigator.swift, PageNavigator.swift

#if canImport(UIKit)
import UIKit

/// A single page of paginated text (TextKit 1 based).
struct NativePageInfo: Sendable, Equatable {
    /// Zero-based page index.
    let pageIndex: Int
    /// UTF-16 character range within the original text.
    let charRange: NSRange
}

/// Paginates plain or attributed text into viewport-sized pages using TextKit 1.
///
/// Usage:
/// ```swift
/// let paginator = NativeTextPaginator()
/// let pages = paginator.paginate(text: content, font: .systemFont(ofSize: 17),
///                                 viewportSize: CGSize(width: 375, height: 667))
/// print("Total pages: \(paginator.totalPages)")
/// ```
@MainActor
final class NativeTextPaginator {

    /// The computed pages from the last `paginate()` or `paginateAttributed()` call.
    private(set) var pages: [NativePageInfo] = []

    /// Total number of pages.
    var totalPages: Int { pages.count }

    // MARK: - Public API

    /// Paginate plain text into pages that fit the viewport.
    ///
    /// - Parameters:
    ///   - text: The plain text to paginate.
    ///   - font: The font used for rendering.
    ///   - viewportSize: The size of one page (width and height in points).
    /// - Returns: Array of `NativePageInfo` describing each page.
    @discardableResult
    func paginate(text: String, font: UIFont, viewportSize: CGSize) -> [NativePageInfo] {
        guard !text.isEmpty else {
            pages = []
            return pages
        }

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping

        let attributedString = NSAttributedString(
            string: text,
            attributes: [.font: font, .paragraphStyle: style]
        )
        return paginateAttributed(attributedText: attributedString, viewportSize: viewportSize)
    }

    /// Paginate an attributed string into pages that fit the viewport.
    /// Use this for MD-rendered content that already has styling.
    ///
    /// - Parameters:
    ///   - attributedText: The styled text to paginate.
    ///   - viewportSize: The size of one page (width and height in points).
    /// - Returns: Array of `NativePageInfo` describing each page.
    @discardableResult
    func paginateAttributed(
        attributedText: NSAttributedString,
        viewportSize: CGSize
    ) -> [NativePageInfo] {
        pages = []

        guard attributedText.length > 0 else { return pages }
        guard viewportSize.width > 0, viewportSize.height > 0 else { return pages }

        // Build TextKit 1 stack
        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        // Add text containers one at a time until all glyphs are laid out.
        // Each container has the viewport size — the layout manager fills them
        // sequentially, like pages of a book.
        var result: [NativePageInfo] = []
        var allGlyphsLaid = false

        while !allGlyphsLaid {
            let container = NSTextContainer(size: viewportSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)

            // Force layout for this container
            layoutManager.ensureLayout(for: container)

            // Get the glyph range laid out in this container
            let glyphRange = layoutManager.glyphRange(for: container)

            if glyphRange.length == 0 {
                // No more glyphs to lay out — we're done
                // Remove the empty container (it was added speculatively)
                layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
                allGlyphsLaid = true
            } else {
                // Convert glyph range to character range
                let charRange = layoutManager.characterRange(
                    forGlyphRange: glyphRange, actualGlyphRange: nil
                )

                result.append(NativePageInfo(
                    pageIndex: result.count,
                    charRange: charRange
                ))

                // Check if we've laid out all glyphs
                let totalGlyphs = layoutManager.numberOfGlyphs
                let lastGlyph = glyphRange.location + glyphRange.length
                if lastGlyph >= totalGlyphs {
                    allGlyphsLaid = true
                }
            }
        }

        pages = result
        return pages
    }

    /// Returns the page index containing the given UTF-16 offset, or nil if out of range.
    func pageContaining(offsetUTF16: Int) -> Int? {
        guard offsetUTF16 >= 0 else { return nil }
        for page in pages {
            let start = page.charRange.location
            let end = start + page.charRange.length
            if offsetUTF16 >= start && offsetUTF16 < end {
                return page.pageIndex
            }
        }
        return nil
    }
}
#endif
