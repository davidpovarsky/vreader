// Purpose: TextKit 2 paginator that divides text into viewport-sized pages.
// Uses NSTextContentStorage + NSTextLayoutManager (iOS 16+/TextKit 2) to lay out text
// and calculate which text ranges fit per viewport height.
// Supports both plain text (uniform font) and pre-formatted attributed text (WI-B05).
//
// Key decisions:
// - @MainActor because TextKit layout managers require main-thread access.
// - Pages use NSRange (UTF-16) to match UIKit/NSString conventions.
// - Empty text produces zero pages.
// - Re-pagination is supported: calling paginate() again replaces prior results.
// - Text container width matches viewport width; height is unconstrained so we get
//   full layout, then we slice by viewport height.
// - paginateAttributed() preserves NSAttributedString formatting (bold, italic, headings).
//
// @coordinates-with: TextKit2PaginatorTests.swift, UnifiedMDTests.swift, SPIKE_RESULTS.md

import UIKit

/// A single page of paginated text.
struct TextKit2PageInfo: Sendable, Equatable {
    /// Zero-based page index.
    let pageIndex: Int
    /// UTF-16 range within the original text.
    let textRange: NSRange
    /// The text content of this page.
    let text: String
}

/// Paginates plain text into viewport-sized pages using TextKit 2.
///
/// Usage:
/// ```swift
/// let paginator = TextKit2Paginator()
/// let pages = paginator.paginate(text: content, font: .systemFont(ofSize: 17),
///                                 viewportSize: CGSize(width: 375, height: 667))
/// print("Total pages: \(paginator.totalPages)")
/// ```
@MainActor
final class TextKit2Paginator {

    /// The computed pages from the last `paginate()` call.
    private(set) var pages: [TextKit2PageInfo] = []

    /// Total number of pages.
    var totalPages: Int { pages.count }

    /// Paginate the given text into pages that fit the viewport.
    ///
    /// - Parameters:
    ///   - text: The plain text to paginate.
    ///   - font: The font used for rendering.
    ///   - viewportSize: The size of one page (width and height in points).
    /// - Returns: Array of `TextKit2PageInfo` describing each page.
    @discardableResult
    func paginate(text: String, font: UIFont, viewportSize: CGSize) -> [TextKit2PageInfo] {
        pages = []

        guard !text.isEmpty else { return pages }
        guard viewportSize.width > 0, viewportSize.height > 0 else { return pages }

        let nsString = text as NSString

        // Set up TextKit 2 stack
        let textContentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(
            width: viewportSize.width,
            height: 0 // Unconstrained height — lay out everything
        ))
        textContainer.lineFragmentPadding = 0

        textLayoutManager.textContainer = textContainer
        textContentStorage.addTextLayoutManager(textLayoutManager)

        // Set the text with the specified font
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle,
            ]
        )
        textContentStorage.textStorage?.setAttributedString(attributedString)

        // Force layout to complete
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)

        // Collect all layout fragment origins, heights, and UTF-16 ranges
        var lines: [FragmentInfo] = []

        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            // Use the fragment's rangeInElement (NSTextRange)
            let fragmentRange = fragment.rangeInElement
            let nsRange = NSRange(fragmentRange, in: textContentStorage)
            lines.append(FragmentInfo(origin: frame.origin, height: frame.height, textRange: nsRange))
            return true // continue enumeration
        }

        guard !lines.isEmpty else {
            // Edge case: layout produced no fragments (shouldn't happen for non-empty text)
            // Fallback: treat entire text as one page
            pages = [TextKit2PageInfo(
                pageIndex: 0,
                textRange: NSRange(location: 0, length: nsString.length),
                text: text
            )]
            return pages
        }

        // Slice lines into pages based on viewport height
        let pageHeight = viewportSize.height
        var pageStartLineIdx = 0
        var currentPageTop = lines[0].origin.y
        var result: [TextKit2PageInfo] = []

        for i in 0..<lines.count {
            let lineBottom = lines[i].origin.y + lines[i].height - currentPageTop

            if lineBottom > pageHeight && i > pageStartLineIdx {
                // Lines [pageStartLineIdx..<i] form a page
                let pageRange = mergedRange(lines: lines, from: pageStartLineIdx, to: i - 1)
                let pageText = nsString.substring(with: pageRange)
                result.append(TextKit2PageInfo(
                    pageIndex: result.count,
                    textRange: pageRange,
                    text: pageText
                ))
                pageStartLineIdx = i
                currentPageTop = lines[i].origin.y
            }
        }

        // Last page: remaining lines
        if pageStartLineIdx < lines.count {
            let pageRange = mergedRange(lines: lines, from: pageStartLineIdx, to: lines.count - 1)
            let pageText = nsString.substring(with: pageRange)
            result.append(TextKit2PageInfo(
                pageIndex: result.count,
                textRange: pageRange,
                text: pageText
            ))
        }

        pages = result
        return pages
    }

    /// Paginate pre-formatted attributed text into pages that fit the viewport.
    ///
    /// Unlike `paginate(text:font:viewportSize:)` which applies a uniform font,
    /// this method preserves all existing attributes (bold, italic, heading sizes, etc.)
    /// from the input attributed string. The `font` parameter is only used as a fallback
    /// for ranges that lack a `.font` attribute.
    ///
    /// - Parameters:
    ///   - attributedText: The attributed text to paginate. Formatting is preserved.
    ///   - font: Fallback font for ranges without a `.font` attribute.
    ///   - viewportSize: The size of one page (width and height in points).
    /// - Returns: Array of `TextKit2PageInfo` describing each page.
    @discardableResult
    func paginateAttributed(
        attributedText: NSAttributedString,
        font: UIFont,
        viewportSize: CGSize
    ) -> [TextKit2PageInfo] {
        pages = []

        guard attributedText.length > 0 else { return pages }
        guard viewportSize.width > 0, viewportSize.height > 0 else { return pages }

        let nsString = attributedText.string as NSString

        // Set up TextKit 2 stack
        let textContentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(
            width: viewportSize.width,
            height: 0 // Unconstrained height — lay out everything
        ))
        textContainer.lineFragmentPadding = 0

        textLayoutManager.textContainer = textContainer
        textContentStorage.addTextLayoutManager(textLayoutManager)

        // Use the attributed string directly to preserve formatting
        textContentStorage.textStorage?.setAttributedString(attributedText)

        // Force layout to complete
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)

        // Collect all layout fragment origins, heights, and UTF-16 ranges
        var lines: [FragmentInfo] = []

        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            let fragmentRange = fragment.rangeInElement
            let nsRange = NSRange(fragmentRange, in: textContentStorage)
            lines.append(FragmentInfo(origin: frame.origin, height: frame.height, textRange: nsRange))
            return true
        }

        guard !lines.isEmpty else {
            pages = [TextKit2PageInfo(
                pageIndex: 0,
                textRange: NSRange(location: 0, length: nsString.length),
                text: attributedText.string
            )]
            return pages
        }

        // Slice lines into pages based on viewport height
        let pageHeight = viewportSize.height
        var pageStartLineIdx = 0
        var currentPageTop = lines[0].origin.y
        var result: [TextKit2PageInfo] = []

        for i in 0..<lines.count {
            let lineBottom = lines[i].origin.y + lines[i].height - currentPageTop

            if lineBottom > pageHeight && i > pageStartLineIdx {
                let pageRange = mergedRange(lines: lines, from: pageStartLineIdx, to: i - 1)
                let pageText = nsString.substring(with: pageRange)
                result.append(TextKit2PageInfo(
                    pageIndex: result.count,
                    textRange: pageRange,
                    text: pageText
                ))
                pageStartLineIdx = i
                currentPageTop = lines[i].origin.y
            }
        }

        // Last page: remaining lines
        if pageStartLineIdx < lines.count {
            let pageRange = mergedRange(lines: lines, from: pageStartLineIdx, to: lines.count - 1)
            let pageText = nsString.substring(with: pageRange)
            result.append(TextKit2PageInfo(
                pageIndex: result.count,
                textRange: pageRange,
                text: pageText
            ))
        }

        pages = result
        return pages
    }

    /// Returns the page index containing the given UTF-16 offset, or nil if out of range.
    func pageContaining(offsetUTF16: Int) -> Int? {
        guard offsetUTF16 >= 0 else { return nil }
        for page in pages {
            let start = page.textRange.location
            let end = start + page.textRange.length
            if offsetUTF16 >= start && offsetUTF16 < end {
                return page.pageIndex
            }
        }
        return nil
    }

    // MARK: - Private Helpers

    /// Merges the text ranges of fragments[from...to] into a single contiguous NSRange.
    private func mergedRange(lines: [FragmentInfo], from: Int, to: Int) -> NSRange {
        let start = lines[from].textRange.location
        let endLine = lines[to]
        let end = endLine.textRange.location + endLine.textRange.length
        return NSRange(location: start, length: end - start)
    }

    /// Layout fragment info for page slicing.
    private struct FragmentInfo {
        let origin: CGPoint
        let height: CGFloat
        let textRange: NSRange
    }
}

// MARK: - NSRange conversion from NSTextRange

extension NSRange {
    /// Converts a TextKit 2 NSTextRange to an NSRange (UTF-16) using the content storage.
    init(_ textRange: NSTextRange, in contentStorage: NSTextContentStorage) {
        let docStart = contentStorage.documentRange.location
        let start = contentStorage.offset(from: docStart, to: textRange.location)
        let length = contentStorage.offset(from: textRange.location, to: textRange.endLocation)
        self.init(location: start, length: length)
    }
}
