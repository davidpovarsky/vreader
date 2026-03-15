// Purpose: Tests for TOCBuilder.forMD — Markdown heading extraction for TOC.

import Testing
import Foundation
@testable import vreader

@Suite("TOCBuilder.forMD")
struct TOCBuilderMDTests {

    // MARK: - Test Helpers

    /// Creates a test fingerprint for MD format.
    private let testFingerprint = DocumentFingerprint(
        contentSHA256: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
        fileByteCount: 500,
        format: .md
    )

    // MARK: - Basic Extraction

    @Test("extracts H1 headings as level 0")
    func extractsH1Headings() {
        let text = "# Title"
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 1)
        #expect(entries[0].title == "Title")
        #expect(entries[0].level == 0)
    }

    @Test("extracts H2 and H3 headings")
    func extractsH2H3() {
        let text = """
        ## Subtitle
        ### Sub-subtitle
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "Subtitle")
        #expect(entries[0].level == 1)
        #expect(entries[1].title == "Sub-subtitle")
        #expect(entries[1].level == 2)
    }

    @Test("extracts all heading levels H1-H6")
    func extractsAllLevels() {
        let text = """
        # H1
        ## H2
        ### H3
        #### H4
        ##### H5
        ###### H6
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 6)
        for i in 0..<6 {
            #expect(entries[i].level == i)
        }
    }

    // MARK: - Fenced Code Blocks

    @Test("ignores headings inside fenced code blocks")
    func ignoresHashesInFencedCodeBlocks() {
        let text = """
        # Real Heading
        ```
        # Not a heading
        ## Also not a heading
        ```
        # Another Real Heading
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "Real Heading")
        #expect(entries[1].title == "Another Real Heading")
    }

    @Test("handles nested fenced blocks (quadruple backtick contains triple)")
    func nestedFencedBlocks() {
        let text = """
        # Before
        ````
        Some text
        ```
        # Not a heading inside nested fence
        ```
        More text
        ````
        # After
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "Before")
        #expect(entries[1].title == "After")
    }

    @Test("ignores headings inside tilde fenced code blocks")
    func ignoresTildeFencedBlocks() {
        let text = """
        # Real
        ~~~
        # Fake
        ~~~
        # Also Real
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "Real")
        #expect(entries[1].title == "Also Real")
    }

    // MARK: - Non-Headings

    @Test("ignores inline hashes (not at start of line)")
    func ignoresInlineHashes() {
        let text = """
        some # text in the middle
        also not ## a heading
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.isEmpty)
    }

    @Test("ignores hash-only lines without title text")
    func ignoresHashOnlyLines() {
        let text = """
        #
        ##
        ###
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.isEmpty)
    }

    @Test("ignores headings without space after hashes")
    func ignoresNoSpaceAfterHash() {
        let text = "#NoSpace\n##AlsoNo"
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.isEmpty)
    }

    // MARK: - Empty/Edge Cases

    @Test("empty text returns empty array")
    func emptyTextReturnsEmpty() {
        let entries = TOCBuilder.forMD(text: "", fingerprint: testFingerprint)

        #expect(entries.isEmpty)
    }

    @Test("text without headings returns empty array")
    func noHeadingsReturnsEmpty() {
        let text = """
        Just some regular text.
        Nothing special here.
        No headings at all.
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.isEmpty)
    }

    // MARK: - Order and Structure

    @Test("preserves document order and correct levels")
    func preservesOrderAndLevel() {
        let text = """
        # Chapter 1
        ## Section 1.1
        ## Section 1.2
        # Chapter 2
        ### Deep Section
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 5)
        #expect(entries[0].title == "Chapter 1")
        #expect(entries[0].level == 0)
        #expect(entries[1].title == "Section 1.1")
        #expect(entries[1].level == 1)
        #expect(entries[2].title == "Section 1.2")
        #expect(entries[2].level == 1)
        #expect(entries[3].title == "Chapter 2")
        #expect(entries[3].level == 0)
        #expect(entries[4].title == "Deep Section")
        #expect(entries[4].level == 2)
    }

    // MARK: - ATX Only

    @Test("only handles ATX headings (no setext)")
    func handlesATXOnly() {
        let text = """
        Setext H1
        =========
        Setext H2
        ---------
        # Real ATX Heading
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 1)
        #expect(entries[0].title == "Real ATX Heading")
    }

    // MARK: - Unicode / Special Characters

    @Test("headings with CJK characters")
    func headingsWithCJK() {
        let text = """
        # 第一章 概述
        ## セクション1
        ### 제3절
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 3)
        #expect(entries[0].title == "第一章 概述")
        #expect(entries[1].title == "セクション1")
        #expect(entries[2].title == "제3절")
    }

    @Test("headings with diacritics and special characters")
    func headingsWithDiacritics() {
        let text = """
        # Über die Philosophie
        ## Résumé
        ### Naïve approach — pros & cons
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 3)
        #expect(entries[0].title == "Über die Philosophie")
        #expect(entries[1].title == "Résumé")
        #expect(entries[2].title == "Naïve approach — pros & cons")
    }

    // MARK: - Whitespace Handling

    @Test("trims trailing whitespace from heading titles")
    func trimsTrailingWhitespace() {
        let text = "# Title with trailing spaces   \n## Another   "
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "Title with trailing spaces")
        #expect(entries[1].title == "Another")
    }

    @Test("strips trailing ATX closing hashes")
    func stripsClosingHashes() {
        let text = "# Title ##\n## Section ###"
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "Title")
        #expect(entries[1].title == "Section")
    }

    // MARK: - Locator Verification

    @Test("entries have valid locators with correct fingerprint")
    func entriesHaveValidLocators() {
        let text = "# Heading"
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 1)
        #expect(entries[0].locator.bookFingerprint == testFingerprint)
    }

    @Test("sequential entries have sequential index in IDs")
    func sequentialEntriesHaveSequentialIds() {
        let text = """
        # First
        ## Second
        ### Third
        """
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 3)
        // IDs should be distinct
        let ids = Set(entries.map(\.id))
        #expect(ids.count == 3)
    }

    // MARK: - UTF-16 Offset Verification

    @Test("heading offsets are correct for multiple headings with body text")
    func headingOffsetsAreCorrect() {
        // Layout (UTF-16 offsets):
        //   "# First\nSome text\n## Second\nMore\n### Third"
        //    0       8         18        28   33
        let text = "# First\nSome text\n## Second\nMore\n### Third"
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 3)
        #expect(entries[0].locator.charOffsetUTF16 == 0)
        #expect(entries[1].locator.charOffsetUTF16 == 18)
        #expect(entries[2].locator.charOffsetUTF16 == 33)
    }

    @Test("second heading offset accounts for first line")
    func secondHeadingOffsetAccountsForFirstLine() {
        // "Hello world\n# Heading"
        //  0           12
        let text = "Hello world\n# Heading"
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 1)
        #expect(entries[0].locator.charOffsetUTF16 == 12)
    }

    @Test("heading offset is zero when heading is on first line")
    func headingOffsetIsZeroOnFirstLine() {
        let text = "# First Line Heading"
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 1)
        #expect(entries[0].locator.charOffsetUTF16 == 0)
    }

    @Test("heading offsets with CJK characters")
    func headingOffsetsWithCJK() {
        // "# Title\n你好世界\n## Next"
        // "# Title" = 7, +\n = 8
        // "你好世界" = 4 UTF-16 code units, +\n = 13
        // "## Next" starts at 13
        let text = "# Title\n你好世界\n## Next"
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].locator.charOffsetUTF16 == 0)
        #expect(entries[1].locator.charOffsetUTF16 == 13)
    }

    @Test("heading offsets with emoji surrogate pairs")
    func headingOffsetsWithEmoji() {
        // "# Start\n😀text\n## End"
        // "# Start" = 7, +\n = 8
        // "😀" = 2 UTF-16 code units, "text" = 4, +\n → offset 15
        // "## End" starts at 15
        let text = "# Start\n😀text\n## End"
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].locator.charOffsetUTF16 == 0)
        #expect(entries[1].locator.charOffsetUTF16 == 15)
    }

    @Test("heading offsets skip fenced code blocks correctly")
    func headingOffsetsSkipFencedCode() {
        // "# Before\n```\n# Fake\n```\n# After"
        // "# Before" = 8, +\n = 9
        // "```" = 3, +\n = 13
        // "# Fake" = 6, +\n = 20
        // "```" = 3, +\n = 24
        // "# After" starts at 24
        let text = "# Before\n```\n# Fake\n```\n# After"
        let entries = TOCBuilder.forMD(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].locator.charOffsetUTF16 == 0)
        #expect(entries[1].locator.charOffsetUTF16 == 24)
    }
}
