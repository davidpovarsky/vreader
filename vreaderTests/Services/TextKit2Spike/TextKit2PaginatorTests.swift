// Purpose: Tests for TextKit 2 reflow engine spike.
// Validates pagination correctness, CJK handling, determinism, and offset mapping.
//
// Key decisions:
// - Uses real UIFont (not mocked) because accurate text measurement is required.
// - @MainActor tests because TextKit 2 layout requires main thread.
// - Generates large text programmatically for stress tests.
//
// @coordinates-with: TextKit2Paginator.swift

import Testing
import UIKit
@testable import vreader

@Suite("TextKit2Paginator")
@MainActor
struct TextKit2PaginatorTests {

    // MARK: - Helpers

    private let defaultFont = UIFont.systemFont(ofSize: 17)
    /// A viewport that resembles an iPhone screen in portrait (logical points).
    private let phoneViewport = CGSize(width: 375, height: 667)

    /// Generates a long string by repeating a line.
    private func generateLongText(lineCount: Int, lineContent: String = "This is a line of text for pagination testing.") -> String {
        (0..<lineCount).map { _ in lineContent }.joined(separator: "\n")
    }

    /// Generates CJK text of approximately the given character count.
    private func generateCJKText(charCount: Int) -> String {
        let base = "这是一段用于测试分页引擎的中文文本。每一行都包含足够多的汉字来填充页面宽度。"
        var result = ""
        while result.count < charCount {
            result += base + "\n"
        }
        return String(result.prefix(charCount))
    }

    // MARK: - Basic Pagination

    @Test func paginate_singlePageText_returns1Page() {
        let paginator = TextKit2Paginator()
        let pages = paginator.paginate(
            text: "Hello, world!",
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count == 1)
        #expect(paginator.totalPages == 1)
        #expect(pages[0].pageIndex == 0)
        #expect(pages[0].text == "Hello, world!")
    }

    @Test func paginate_multiPageText_returnsCorrectPageCount() {
        let paginator = TextKit2Paginator()
        // 500 lines should definitely overflow a single phone viewport
        let longText = generateLongText(lineCount: 500)
        let pages = paginator.paginate(
            text: longText,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count > 1, "500 lines of text must span more than 1 page")
        #expect(paginator.totalPages == pages.count)
        // Pages should be numbered sequentially
        for (i, page) in pages.enumerated() {
            #expect(page.pageIndex == i, "Page \(i) should have pageIndex \(i)")
        }
    }

    @Test func paginate_emptyText_returns0Pages() {
        let paginator = TextKit2Paginator()
        let pages = paginator.paginate(
            text: "",
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.isEmpty)
        #expect(paginator.totalPages == 0)
    }

    // MARK: - CJK Handling

    @Test func paginate_cjkText_correctBoundaries() {
        let paginator = TextKit2Paginator()
        let cjkText = generateCJKText(charCount: 5000)
        let pages = paginator.paginate(
            text: cjkText,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count > 1, "5000 CJK characters should span multiple pages")

        // Verify no page's text range splits a CJK character
        // (i.e., each page's textRange should correspond to valid String indices)
        for page in pages {
            let nsRange = page.textRange
            let nsString = cjkText as NSString
            // Extracting substring with the range should not crash and should match
            let extracted = nsString.substring(with: nsRange)
            #expect(extracted == page.text,
                    "Page \(page.pageIndex) text should match extracted substring")
        }
    }

    @Test func paginate_mixedCJKLatin_noOrphanedLines() {
        let paginator = TextKit2Paginator()
        var mixedLines: [String] = []
        for i in 0..<200 {
            if i % 2 == 0 {
                mixedLines.append("English paragraph number \(i) with some words.")
            } else {
                mixedLines.append("第\(i)段中文文本，包含一些汉字和标点符号。")
            }
        }
        let mixedText = mixedLines.joined(separator: "\n")
        let pages = paginator.paginate(
            text: mixedText,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count > 1, "200 mixed lines should span multiple pages")

        // All text should be accounted for — concatenated page texts equal original
        let reconstructed = pages.map(\.text).joined()
        #expect(reconstructed == mixedText,
                "Concatenated page texts must reconstruct the original text")
    }

    // MARK: - Determinism

    @Test func paginate_deterministic_sameInputSameOutput() {
        let text = generateLongText(lineCount: 100)
        let font = UIFont.systemFont(ofSize: 17)
        let viewport = CGSize(width: 375, height: 667)

        let paginator1 = TextKit2Paginator()
        let pages1 = paginator1.paginate(text: text, font: font, viewportSize: viewport)

        let paginator2 = TextKit2Paginator()
        let pages2 = paginator2.paginate(text: text, font: font, viewportSize: viewport)

        #expect(pages1.count == pages2.count, "Same input must produce same page count")
        for i in 0..<pages1.count {
            #expect(pages1[i].textRange == pages2[i].textRange,
                    "Page \(i) range must be identical across runs")
            #expect(pages1[i].text == pages2[i].text,
                    "Page \(i) text must be identical across runs")
        }
    }

    // MARK: - Page Lookup

    @Test func pageAtIndex_returnsCorrectTextRange() {
        let paginator = TextKit2Paginator()
        let longText = generateLongText(lineCount: 300)
        let pages = paginator.paginate(
            text: longText,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count >= 3, "Need at least 3 pages for this test")

        // Page 2 (0-indexed) should have valid text
        let page2 = pages[2]
        #expect(!page2.text.isEmpty, "Page 2 should have non-empty text")
        #expect(page2.textRange.location >= 0)
        #expect(page2.textRange.length > 0)

        // Text range should be within bounds
        let nsString = longText as NSString
        #expect(page2.textRange.location + page2.textRange.length <= nsString.length,
                "Page range must not exceed text length")
    }

    @Test func offsetToPage_returnsCorrectPageIndex() {
        let paginator = TextKit2Paginator()
        let longText = generateLongText(lineCount: 300)
        let pages = paginator.paginate(
            text: longText,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count >= 2)

        // Offset 0 should be on page 0
        let page0 = paginator.pageContaining(offsetUTF16: 0)
        #expect(page0 == 0, "Offset 0 should be on page 0")

        // An offset in the middle of page 1 should return page 1
        if pages.count >= 2 {
            let midPage1 = pages[1].textRange.location + pages[1].textRange.length / 2
            let foundPage = paginator.pageContaining(offsetUTF16: midPage1)
            #expect(foundPage == 1, "Mid-page-1 offset should map to page 1")
        }

        // Offset past end should return nil
        let pastEnd = paginator.pageContaining(offsetUTF16: (longText as NSString).length + 1)
        #expect(pastEnd == nil, "Offset past end should return nil")

        // Negative offset should return nil
        let negative = paginator.pageContaining(offsetUTF16: -1)
        #expect(negative == nil, "Negative offset should return nil")
    }

    // MARK: - Recalculation on Parameter Change

    @Test func viewportChange_recalculatesPages() {
        let text = generateLongText(lineCount: 200)
        let paginator = TextKit2Paginator()

        let pagesLarge = paginator.paginate(
            text: text,
            font: defaultFont,
            viewportSize: CGSize(width: 375, height: 800)
        )
        let pagesSmall = paginator.paginate(
            text: text,
            font: defaultFont,
            viewportSize: CGSize(width: 375, height: 400)
        )

        #expect(pagesSmall.count > pagesLarge.count,
                "Smaller viewport should produce more pages (\(pagesSmall.count) vs \(pagesLarge.count))")
    }

    @Test func fontSizeChange_recalculatesPages() {
        let text = generateLongText(lineCount: 200)
        let paginator = TextKit2Paginator()

        let pagesSmallFont = paginator.paginate(
            text: text,
            font: UIFont.systemFont(ofSize: 14),
            viewportSize: phoneViewport
        )
        let pagesLargeFont = paginator.paginate(
            text: text,
            font: UIFont.systemFont(ofSize: 24),
            viewportSize: phoneViewport
        )

        #expect(pagesLargeFont.count > pagesSmallFont.count,
                "Larger font should produce more pages (\(pagesLargeFont.count) vs \(pagesSmallFont.count))")
    }

    // MARK: - Text Coverage (no text lost or duplicated)

    @Test func allPages_coverEntireText_noGapsNoDuplicates() {
        let paginator = TextKit2Paginator()
        let text = generateLongText(lineCount: 150)
        let pages = paginator.paginate(
            text: text,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(!pages.isEmpty)

        // Ranges should be contiguous and non-overlapping
        for i in 1..<pages.count {
            let prevEnd = pages[i - 1].textRange.location + pages[i - 1].textRange.length
            let currStart = pages[i].textRange.location
            #expect(currStart == prevEnd,
                    "Page \(i) should start where page \(i-1) ends: expected \(prevEnd), got \(currStart)")
        }

        // First page starts at 0
        #expect(pages.first!.textRange.location == 0)

        // Last page ends at text length
        let lastPage = pages.last!
        let lastEnd = lastPage.textRange.location + lastPage.textRange.length
        #expect(lastEnd == (text as NSString).length,
                "Last page should end at text length \((text as NSString).length), got \(lastEnd)")
    }

    // MARK: - Edge Cases

    @Test func paginate_singleCharacter_returns1Page() {
        let paginator = TextKit2Paginator()
        let pages = paginator.paginate(
            text: "A",
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count == 1)
        #expect(pages[0].text == "A")
    }

    @Test func paginate_onlyNewlines_handledGracefully() {
        let paginator = TextKit2Paginator()
        let text = String(repeating: "\n", count: 500)
        let pages = paginator.paginate(
            text: text,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        // Should not crash, and should produce at least 1 page
        // (500 newlines will create visible blank lines that overflow)
        #expect(pages.count >= 1, "500 newlines should produce at least 1 page")
        let reconstructed = pages.map(\.text).joined()
        #expect(reconstructed == text, "Reconstructed text must match original")
    }

    @Test func paginate_veryNarrowViewport_doesNotCrash() {
        let paginator = TextKit2Paginator()
        let text = "Hello, world! This is a test of very narrow viewport handling."
        let pages = paginator.paginate(
            text: text,
            font: defaultFont,
            viewportSize: CGSize(width: 50, height: 100)
        )
        // Should not crash; may produce multiple pages due to narrow width
        #expect(pages.count >= 1)
    }
}
