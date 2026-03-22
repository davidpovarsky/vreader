// Purpose: Tests for WI-B05 — Unified MD Reflow. Validates that attributed text
// (from Markdown rendering) paginates correctly through the Unified engine,
// preserving formatting per page and handling edge cases.
//
// @coordinates-with: UnifiedTextRendererViewModel.swift, TextKit2Paginator.swift
//
// TODO: Re-enable when TextKit2Paginator.paginateAttributed() and
// UnifiedTextRendererViewModel.configureAttributed() are implemented (WI-B05).
#if false
import Testing
import UIKit
@testable import vreader

@Suite("UnifiedMDReflow")
@MainActor
struct UnifiedMDTests {

    // MARK: - Helpers

    private let defaultFont = UIFont.systemFont(ofSize: 17)
    private let phoneViewport = CGSize(width: 375, height: 667)

    /// Creates an NSAttributedString with the given text and font.
    private func makeAttributedString(
        _ text: String,
        font: UIFont? = nil
    ) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font ?? defaultFont,
        ])
    }

    /// Creates a rich NSAttributedString with bold/italic spans for testing.
    private func makeRichAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let normalFont = defaultFont
        let boldFont = UIFont.boldSystemFont(ofSize: 17)
        let italicFont = UIFont.italicSystemFont(ofSize: 17)

        result.append(NSAttributedString(
            string: "Normal text. ",
            attributes: [.font: normalFont]
        ))
        result.append(NSAttributedString(
            string: "Bold text. ",
            attributes: [.font: boldFont]
        ))
        result.append(NSAttributedString(
            string: "Italic text.\n",
            attributes: [.font: italicFont]
        ))

        // Repeat to make multi-page content
        let singleParagraph = NSAttributedString(attributedString: result)
        for _ in 0..<80 {
            result.append(singleParagraph)
        }
        return result
    }

    /// Generates a long attributed string that spans multiple pages.
    private func makeLongAttributedString(lineCount: Int) -> NSAttributedString {
        let text = (0..<lineCount)
            .map { _ in "This is a line of attributed text for unified MD testing." }
            .joined(separator: "\n")
        return makeAttributedString(text)
    }

    /// Generates CJK attributed text.
    private func makeCJKAttributedString(charCount: Int) -> NSAttributedString {
        let base = "这是一段用于测试统一渲染引擎的中文文本。每行包含足够多的汉字来填充页面宽度。"
        var result = ""
        while result.count < charCount {
            result += base + "\n"
        }
        return makeAttributedString(String(result.prefix(charCount)))
    }

    // MARK: - B05: paginateAttributed — correct page count

    @Test func paginateAttributed_correctPageCount() {
        let paginator = TextKit2Paginator()
        let attrStr = makeLongAttributedString(lineCount: 200)
        let pages = paginator.paginateAttributed(
            attributedText: attrStr,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count > 1,
                "200 lines of attributed text should span multiple pages, got \(pages.count)")
        #expect(paginator.totalPages == pages.count)

        // Compare with plain text pagination — should be same since font is same
        let plainPages = paginator.paginate(
            text: attrStr.string,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count == plainPages.count,
                "Attributed with same font should produce same page count as plain text")
    }

    // MARK: - B05: MD formatting preserved per page

    @Test func mdFormatting_preservedPerPage() {
        let paginator = TextKit2Paginator()
        let richAttr = makeRichAttributedString()
        let pages = paginator.paginateAttributed(
            attributedText: richAttr,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count > 1, "Rich content should span multiple pages")

        // Check that page 0 has attributed content with mixed fonts
        let page0Range = pages[0].textRange
        let page0Attr = richAttr.attributedSubstring(from: page0Range)
        var foundBold = false
        page0Attr.enumerateAttribute(.font, in: NSRange(location: 0, length: page0Attr.length)) { value, _, _ in
            if let font = value as? UIFont,
               font.fontDescriptor.symbolicTraits.contains(.traitBold) {
                foundBold = true
            }
        }
        #expect(foundBold, "Page 0 should contain bold text from the rich MD content")
    }

    // MARK: - B05: empty MD file → zero pages

    @Test func emptyMDFile_zeroPages() {
        let paginator = TextKit2Paginator()
        let emptyAttr = NSAttributedString(string: "")
        let pages = paginator.paginateAttributed(
            attributedText: emptyAttr,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.isEmpty, "Empty attributed string should produce zero pages")
        #expect(paginator.totalPages == 0)
    }

    // MARK: - B05: progress persistence in MD unified mode

    @Test func progressPersistence_mdUnified() {
        let attrStr = makeLongAttributedString(lineCount: 200)
        let vm = UnifiedTextRendererViewModel(text: attrStr.string)
        vm.configureAttributed(
            attributedText: attrStr,
            viewportSize: phoneViewport
        )
        #expect(vm.isPagedMode || vm.isScrollMode, "Should be in a valid mode after configure")

        // Configure in paged mode and navigate
        vm.configureAttributed(
            attributedText: attrStr,
            viewportSize: phoneViewport,
            layout: .paged
        )
        #expect(vm.totalPages > 2)

        vm.goToPage(3)
        let progress = vm.progress
        #expect(progress > 0.0, "Progress should be > 0 after navigating to page 3")

        // Reconfigure — progress should be preserved approximately
        vm.configureAttributed(
            attributedText: attrStr,
            viewportSize: phoneViewport,
            layout: .paged
        )
        #expect(abs(vm.progress - progress) < 0.05,
                "Progress should be preserved after reconfiguration")
    }

    // MARK: - B05: CJK attributed text

    @Test func cjkAttributedText_paginatesCorrectly() {
        let paginator = TextKit2Paginator()
        let cjkAttr = makeCJKAttributedString(charCount: 5000)
        let pages = paginator.paginateAttributed(
            attributedText: cjkAttr,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count > 1, "5000 CJK chars should span multiple pages")

        // Verify text coverage
        let reconstructed = pages.map(\.text).joined()
        #expect(reconstructed == cjkAttr.string,
                "Concatenated page texts must reconstruct the original")
    }

    // MARK: - B05: Single character attributed

    @Test func singleCharacterAttributed_returns1Page() {
        let paginator = TextKit2Paginator()
        let attrStr = makeAttributedString("A")
        let pages = paginator.paginateAttributed(
            attributedText: attrStr,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count == 1)
        #expect(pages[0].text == "A")
    }

    // MARK: - B05: ViewModel configureAttributed with attributed text

    @Test func viewModel_configureAttributed_setsPages() {
        let attrStr = makeLongAttributedString(lineCount: 200)
        let vm = UnifiedTextRendererViewModel(text: attrStr.string)
        vm.configureAttributed(
            attributedText: attrStr,
            viewportSize: phoneViewport,
            layout: .paged
        )
        #expect(vm.totalPages > 0, "Should have pages after configureAttributed")
        #expect(vm.currentPageText != nil)
        #expect(!vm.currentPageText!.isEmpty)
    }

    // MARK: - B05: ViewModel configureAttributed in scroll mode

    @Test func viewModel_configureAttributed_scrollMode() {
        let attrStr = makeLongAttributedString(lineCount: 200)
        let vm = UnifiedTextRendererViewModel(text: attrStr.string)
        vm.configureAttributed(
            attributedText: attrStr,
            viewportSize: phoneViewport,
            layout: .scroll
        )
        #expect(vm.isScrollMode)
        #expect(vm.progress == 0.0)

        // Scroll tracking should still work
        let midOffset = (attrStr.string as NSString).length / 2
        vm.updateScrollOffset(charOffsetUTF16: midOffset)
        #expect(vm.progress > 0.4 && vm.progress < 0.6,
                "Progress should be ~0.5 at mid-offset")
    }
}
#endif
