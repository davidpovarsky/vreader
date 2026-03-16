// Purpose: Tests for the Unified TXT Reflow Engine — UnifiedTextRendererViewModel.
// Validates scroll and paged mode rendering logic, page navigation, progress tracking,
// font change recalculation, and edge cases (empty, CJK, single char).
//
// Key decisions:
// - Tests the ViewModel layer (not SwiftUI views) for reliable unit testing.
// - Uses real UIFont + TextKit2Paginator for page count accuracy.
// - @MainActor tests because TextKit 2 layout requires main thread.
//
// @coordinates-with: UnifiedTextRendererViewModel.swift, TextKit2Paginator.swift

import Testing
import UIKit
@testable import vreader

@Suite("UnifiedTextRendererViewModel")
@MainActor
struct UnifiedTextRendererTests {

    // MARK: - Helpers

    private let defaultFont = UIFont.systemFont(ofSize: 17)
    private let phoneViewport = CGSize(width: 375, height: 667)

    /// Creates a ViewModel with the given text and mode, then calls configure().
    private func makeViewModel(
        text: String,
        layout: EPUBLayoutPreference = .scroll,
        font: UIFont? = nil,
        viewport: CGSize? = nil
    ) -> UnifiedTextRendererViewModel {
        let vm = UnifiedTextRendererViewModel(text: text)
        vm.configure(
            font: font ?? defaultFont,
            viewportSize: viewport ?? phoneViewport,
            layout: layout
        )
        return vm
    }

    private func generateLongText(lineCount: Int) -> String {
        (0..<lineCount).map { _ in "This is a line of text for unified renderer testing." }
            .joined(separator: "\n")
    }

    private func generateCJKText(charCount: Int) -> String {
        let base = "这是一段用于测试统一渲染引擎的中文文本。每行包含足够多的汉字来填充页面宽度。"
        var result = ""
        while result.count < charCount {
            result += base + "\n"
        }
        return String(result.prefix(charCount))
    }

    // MARK: - Scroll Mode: Text Display

    @Test func rendersText_inScrollMode() {
        let vm = makeViewModel(text: "Hello, world!", layout: .scroll)
        // In scroll mode, the full text is available
        #expect(vm.text == "Hello, world!")
        #expect(vm.isScrollMode)
        #expect(!vm.isPagedMode)
    }

    // MARK: - Paged Mode: Text Display

    @Test func rendersText_inPagedMode() {
        let longText = generateLongText(lineCount: 100)
        let vm = makeViewModel(text: longText, layout: .paged)
        #expect(vm.isPagedMode)
        #expect(!vm.isScrollMode)
        #expect(vm.totalPages > 0)
        // Current page text should be non-empty
        #expect(vm.currentPageText != nil)
        #expect(!vm.currentPageText!.isEmpty)
    }

    // MARK: - Page Count Matches TextKit2Paginator

    @Test func pageCount_matchesTextKit2Paginator() {
        let longText = generateLongText(lineCount: 200)
        let vm = makeViewModel(text: longText, layout: .paged)

        // Compare with standalone paginator
        let paginator = TextKit2Paginator()
        paginator.paginate(text: longText, font: defaultFont, viewportSize: phoneViewport)

        #expect(vm.totalPages == paginator.totalPages,
                "ViewModel page count (\(vm.totalPages)) must match paginator (\(paginator.totalPages))")
    }

    // MARK: - Navigate to Page

    @Test func navigateToPage_showsCorrectContent() {
        let longText = generateLongText(lineCount: 300)
        let vm = makeViewModel(text: longText, layout: .paged)
        #expect(vm.totalPages >= 4, "Need at least 4 pages for this test")

        // Navigate to page 3 (0-indexed)
        vm.goToPage(3)
        #expect(vm.currentPage == 3)

        // The text should correspond to page 3 from the paginator
        let paginator = TextKit2Paginator()
        paginator.paginate(text: longText, font: defaultFont, viewportSize: phoneViewport)
        let expectedText = paginator.pages[3].text
        #expect(vm.currentPageText == expectedText,
                "Page 3 text should match paginator's page 3 text")
    }

    // MARK: - Font Size Change Recalculates Pages

    @Test func fontSizeChange_recalculatesPages() {
        let longText = generateLongText(lineCount: 200)
        let vm = UnifiedTextRendererViewModel(text: longText)

        vm.configure(
            font: UIFont.systemFont(ofSize: 14),
            viewportSize: phoneViewport,
            layout: .paged
        )
        let smallFontPages = vm.totalPages

        vm.configure(
            font: UIFont.systemFont(ofSize: 24),
            viewportSize: phoneViewport,
            layout: .paged
        )
        let largeFontPages = vm.totalPages

        #expect(largeFontPages > smallFontPages,
                "Larger font (\(largeFontPages)) should produce more pages than smaller font (\(smallFontPages))")
    }

    // MARK: - Scroll Mode Position Tracking

    @Test func scrollMode_positionTracking() {
        let longText = generateLongText(lineCount: 200)
        let vm = makeViewModel(text: longText, layout: .scroll)

        #expect(vm.progress == 0.0, "Initial progress should be 0")

        // Simulate scroll to 50%
        let midOffset = (longText as NSString).length / 2
        vm.updateScrollOffset(charOffsetUTF16: midOffset)

        let expectedProgress = Double(midOffset) / Double((longText as NSString).length)
        #expect(abs(vm.progress - expectedProgress) < 0.01,
                "Progress should be ~\(expectedProgress), got \(vm.progress)")
    }

    // MARK: - Paged Mode Position Tracking

    @Test func pagedMode_positionTracking() {
        let longText = generateLongText(lineCount: 200)
        let vm = makeViewModel(text: longText, layout: .paged)
        #expect(vm.totalPages > 2)

        #expect(vm.progress == 0.0, "Initial progress should be 0")

        // Navigate to last page
        vm.goToPage(vm.totalPages - 1)
        #expect(vm.progress == 1.0, "Progress at last page should be 1.0")

        // Navigate to middle page
        let midPage = vm.totalPages / 2
        vm.goToPage(midPage)
        let expectedProgress = Double(midPage) / Double(vm.totalPages - 1)
        #expect(abs(vm.progress - expectedProgress) < 0.01,
                "Progress at middle page should be ~\(expectedProgress)")
    }

    // MARK: - Empty Text

    @Test func emptyText_handledGracefully() {
        let vm = makeViewModel(text: "", layout: .paged)
        #expect(vm.totalPages == 0)
        #expect(vm.currentPage == 0)
        #expect(vm.currentPageText == nil)
        #expect(vm.progress == 0.0)

        // Navigation should be no-ops
        vm.nextPage()
        #expect(vm.currentPage == 0)
        vm.previousPage()
        #expect(vm.currentPage == 0)
        vm.goToPage(5)
        #expect(vm.currentPage == 0)
    }

    @Test func emptyText_scrollMode_handledGracefully() {
        let vm = makeViewModel(text: "", layout: .scroll)
        #expect(vm.text.isEmpty)
        #expect(vm.progress == 0.0)
        vm.updateScrollOffset(charOffsetUTF16: 100)
        // Should clamp to 0 since totalLength is 0
        #expect(vm.progress == 0.0)
    }

    // MARK: - CJK Text

    @Test func cjkText_rendersCorrectly() {
        let cjkText = generateCJKText(charCount: 5000)
        let vm = makeViewModel(text: cjkText, layout: .paged)
        #expect(vm.totalPages > 1, "5000 CJK characters should span multiple pages")

        // Each page should have valid non-empty text
        for pageIdx in 0..<vm.totalPages {
            vm.goToPage(pageIdx)
            #expect(vm.currentPageText != nil, "Page \(pageIdx) text should not be nil")
            #expect(!vm.currentPageText!.isEmpty, "Page \(pageIdx) text should not be empty")
        }
    }

    // MARK: - Navigation: Next/Previous

    @Test func nextPage_advancesCorrectly() {
        let longText = generateLongText(lineCount: 200)
        let vm = makeViewModel(text: longText, layout: .paged)
        #expect(vm.currentPage == 0)

        vm.nextPage()
        #expect(vm.currentPage == 1)

        vm.nextPage()
        #expect(vm.currentPage == 2)
    }

    @Test func previousPage_goesBackCorrectly() {
        let longText = generateLongText(lineCount: 200)
        let vm = makeViewModel(text: longText, layout: .paged)

        vm.goToPage(3)
        #expect(vm.currentPage == 3)

        vm.previousPage()
        #expect(vm.currentPage == 2)
    }

    @Test func nextPage_atLastPage_isNoOp() {
        let longText = generateLongText(lineCount: 200)
        let vm = makeViewModel(text: longText, layout: .paged)
        let lastPage = vm.totalPages - 1
        vm.goToPage(lastPage)

        vm.nextPage()
        #expect(vm.currentPage == lastPage, "Should stay at last page")
    }

    @Test func previousPage_atFirstPage_isNoOp() {
        let longText = generateLongText(lineCount: 200)
        let vm = makeViewModel(text: longText, layout: .paged)
        #expect(vm.currentPage == 0)

        vm.previousPage()
        #expect(vm.currentPage == 0, "Should stay at page 0")
    }

    // MARK: - Page Clamping

    @Test func goToPage_clampsToValidRange() {
        let longText = generateLongText(lineCount: 200)
        let vm = makeViewModel(text: longText, layout: .paged)

        vm.goToPage(-5)
        #expect(vm.currentPage == 0, "Negative page should clamp to 0")

        vm.goToPage(999999)
        #expect(vm.currentPage == vm.totalPages - 1, "Excess page should clamp to last")
    }

    // MARK: - Mode Switching

    @Test func modeSwitching_preservesProgress() {
        let longText = generateLongText(lineCount: 200)
        let vm = UnifiedTextRendererViewModel(text: longText)

        // Start in paged mode, navigate to page 3
        vm.configure(font: defaultFont, viewportSize: phoneViewport, layout: .paged)
        vm.goToPage(3)
        let pagedProgress = vm.progress

        // Switch to scroll mode — progress should be preserved (approximately)
        vm.configure(font: defaultFont, viewportSize: phoneViewport, layout: .scroll)
        #expect(abs(vm.progress - pagedProgress) < 0.05,
                "Progress should be approximately preserved on mode switch")
    }

    // MARK: - Single Character

    @Test func singleCharacter_returns1Page() {
        let vm = makeViewModel(text: "A", layout: .paged)
        #expect(vm.totalPages == 1)
        #expect(vm.currentPageText == "A")
    }

    // MARK: - Offset from Progress (for scroll mode seeking)

    @Test func charOffsetFromProgress_computesCorrectly() {
        let longText = generateLongText(lineCount: 100)
        let vm = makeViewModel(text: longText, layout: .scroll)
        let totalLen = (longText as NSString).length

        // 50% progress — allow rounding difference of 1
        let offset50 = vm.charOffsetForProgress(0.5)
        #expect(abs(offset50 - totalLen / 2) <= 1, "50% progress should yield ~mid-offset")

        // 0% progress
        let offset0 = vm.charOffsetForProgress(0.0)
        #expect(offset0 == 0)

        // 100% progress
        let offset100 = vm.charOffsetForProgress(1.0)
        #expect(offset100 == totalLen)
    }
}
