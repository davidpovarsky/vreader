// Purpose: Tests for FoliateTOCConverter — converts Foliate-js TOC tree to flat [TOCEntry].

import Testing
import Foundation
@testable import vreader

@Suite("FoliateTOCConverter")
struct FoliateTOCConverterTests {

    // MARK: - Test Helpers

    /// Creates a valid DocumentFingerprint for testing.
    private func makeFingerprint(format: BookFormat = .azw3) -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
            fileByteCount: 5000,
            format: format
        )
    }

    /// Creates a FoliateTOCItem with no subitems.
    private func leaf(_ label: String, href: String = "section.xhtml") -> FoliateTOCItem {
        FoliateTOCItem(label: label, href: href, subitems: [])
    }

    // MARK: - Empty Input

    @Test("empty input returns empty output")
    func emptyInput() {
        let result = FoliateTOCConverter.convert([], fingerprint: makeFingerprint())
        #expect(result.isEmpty)
    }

    // MARK: - Single Item

    @Test("single item returns single entry at level 0")
    func singleItem() {
        let items = [leaf("Cover", href: "cover.xhtml")]
        let result = FoliateTOCConverter.convert(items, fingerprint: makeFingerprint())

        #expect(result.count == 1)
        #expect(result[0].title == "Cover")
        #expect(result[0].level == 0)
    }

    // MARK: - Flat List

    @Test("flat list produces entries with level 0")
    func flatList() {
        let items = [
            leaf("Chapter 1", href: "ch1.xhtml"),
            leaf("Chapter 2", href: "ch2.xhtml"),
            leaf("Chapter 3", href: "ch3.xhtml"),
        ]
        let result = FoliateTOCConverter.convert(items, fingerprint: makeFingerprint())

        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.level == 0 })
        #expect(result[0].title == "Chapter 1")
        #expect(result[1].title == "Chapter 2")
        #expect(result[2].title == "Chapter 3")
    }

    // MARK: - Nested Two Levels

    @Test("nested 2-level assigns correct levels")
    func nestedTwoLevels() {
        let items = [
            FoliateTOCItem(label: "Part I", href: "part1.xhtml", subitems: [
                leaf("Chapter 1", href: "ch1.xhtml"),
                leaf("Chapter 2", href: "ch2.xhtml"),
            ]),
            FoliateTOCItem(label: "Part II", href: "part2.xhtml", subitems: [
                leaf("Chapter 3", href: "ch3.xhtml"),
            ]),
        ]
        let result = FoliateTOCConverter.convert(items, fingerprint: makeFingerprint())

        #expect(result.count == 5)
        #expect(result[0].title == "Part I")
        #expect(result[0].level == 0)
        #expect(result[1].title == "Chapter 1")
        #expect(result[1].level == 1)
        #expect(result[2].title == "Chapter 2")
        #expect(result[2].level == 1)
        #expect(result[3].title == "Part II")
        #expect(result[3].level == 0)
        #expect(result[4].title == "Chapter 3")
        #expect(result[4].level == 1)
    }

    // MARK: - Deep Nesting (3 Levels)

    @Test("deep nesting 3 levels assigns levels 0, 1, 2")
    func deepNestingThreeLevels() {
        let items = [
            FoliateTOCItem(label: "Book", href: "book.xhtml", subitems: [
                FoliateTOCItem(label: "Part", href: "part.xhtml", subitems: [
                    leaf("Section", href: "section.xhtml"),
                ]),
            ]),
        ]
        let result = FoliateTOCConverter.convert(items, fingerprint: makeFingerprint())

        #expect(result.count == 3)
        #expect(result[0].title == "Book")
        #expect(result[0].level == 0)
        #expect(result[1].title == "Part")
        #expect(result[1].level == 1)
        #expect(result[2].title == "Section")
        #expect(result[2].level == 2)
    }

    // MARK: - Depth-First Order

    @Test("output is depth-first: parent, child, child, next parent")
    func depthFirstOrder() {
        let items = [
            FoliateTOCItem(label: "A", href: "a.xhtml", subitems: [
                leaf("A1", href: "a1.xhtml"),
                leaf("A2", href: "a2.xhtml"),
            ]),
            leaf("B", href: "b.xhtml"),
        ]
        let result = FoliateTOCConverter.convert(items, fingerprint: makeFingerprint())

        let titles = result.map(\.title)
        #expect(titles == ["A", "A1", "A2", "B"])
    }

    // MARK: - Labels Preserved

    @Test("labels are preserved as titles")
    func labelsPreserved() {
        let items = [leaf("Introduction")]
        let result = FoliateTOCConverter.convert(items, fingerprint: makeFingerprint())

        #expect(result[0].title == "Introduction")
    }

    // MARK: - Labels Trimmed

    @Test("labels with leading/trailing whitespace are trimmed")
    func labelsTrimmed() {
        let items = [leaf("  Chapter 1  ", href: "ch1.xhtml")]
        let result = FoliateTOCConverter.convert(items, fingerprint: makeFingerprint())

        #expect(result[0].title == "Chapter 1")
    }

    // MARK: - Whitespace-Only Labels Skipped

    @Test("whitespace-only labels are skipped")
    func whitespaceOnlyLabelsSkipped() {
        let items = [
            leaf("   ", href: "blank.xhtml"),
            leaf("Chapter 1", href: "ch1.xhtml"),
            leaf("", href: "empty.xhtml"),
        ]
        let result = FoliateTOCConverter.convert(items, fingerprint: makeFingerprint())

        #expect(result.count == 1)
        #expect(result[0].title == "Chapter 1")
    }

    // MARK: - Hrefs Preserved in Locators

    @Test("hrefs are preserved in locators")
    func hrefsPreservedInLocators() {
        let items = [leaf("Chapter 1", href: "content/ch1.xhtml")]
        let result = FoliateTOCConverter.convert(items, fingerprint: makeFingerprint())

        #expect(result[0].locator.href == "content/ch1.xhtml")
    }

    // MARK: - CJK Labels

    @Test("CJK labels are handled correctly")
    func cjkLabels() {
        let items = [
            leaf("\u{7B2C}\u{4E00}\u{7AE0}", href: "ch1.xhtml"),   // 第一章
            leaf("\u{7B2C}\u{4E8C}\u{7AE0}", href: "ch2.xhtml"),   // 第二章
        ]
        let result = FoliateTOCConverter.convert(items, fingerprint: makeFingerprint())

        #expect(result.count == 2)
        #expect(result[0].title == "\u{7B2C}\u{4E00}\u{7AE0}")
        #expect(result[1].title == "\u{7B2C}\u{4E8C}\u{7AE0}")
    }

    // MARK: - Sequence Index

    @Test("sequence indices are globally sequential across all levels")
    func sequenceIndicesSequential() {
        let items = [
            FoliateTOCItem(label: "Part I", href: "p1.xhtml", subitems: [
                leaf("Ch 1", href: "ch1.xhtml"),
            ]),
            leaf("Part II", href: "p2.xhtml"),
        ]
        let result = FoliateTOCConverter.convert(items, fingerprint: makeFingerprint())

        // All entries should have unique IDs (which include sequenceIndex)
        let ids = result.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "All IDs should be unique")
    }

    // MARK: - Fingerprint Propagated

    @Test("fingerprint is propagated to all locators")
    func fingerprintPropagated() {
        let fp = makeFingerprint()
        let items = [
            FoliateTOCItem(label: "A", href: "a.xhtml", subitems: [
                leaf("B", href: "b.xhtml"),
            ]),
        ]
        let result = FoliateTOCConverter.convert(items, fingerprint: fp)

        #expect(result.allSatisfy { $0.locator.bookFingerprint == fp })
    }

    // MARK: - Nested Whitespace-Only Skipped Without Breaking Tree

    @Test("whitespace-only children are skipped without affecting sibling indices")
    func nestedWhitespaceOnlySkipped() {
        let items = [
            FoliateTOCItem(label: "Part I", href: "p1.xhtml", subitems: [
                leaf("  ", href: "blank.xhtml"),
                leaf("Chapter 1", href: "ch1.xhtml"),
            ]),
        ]
        let result = FoliateTOCConverter.convert(items, fingerprint: makeFingerprint())

        #expect(result.count == 2)
        #expect(result[0].title == "Part I")
        #expect(result[0].level == 0)
        #expect(result[1].title == "Chapter 1")
        #expect(result[1].level == 1)
    }

    // MARK: - EPUB Format Works Too

    @Test("converter works with EPUB format fingerprint")
    func epubFormatWorks() {
        let fp = makeFingerprint(format: .epub)
        let items = [leaf("Chapter 1", href: "ch1.xhtml")]
        let result = FoliateTOCConverter.convert(items, fingerprint: fp)

        #expect(result.count == 1)
        #expect(result[0].locator.bookFingerprint.format == .epub)
    }
}
