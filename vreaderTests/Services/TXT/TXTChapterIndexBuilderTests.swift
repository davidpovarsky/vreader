// Purpose: Tests for TXTChapterIndexBuilder — streaming chapter index from byte data.
// Covers: empty file, small file, regex matches, byte contiguity, block boundaries,
//         synthetic chapters, CJK encoding, EOF handling, single match fallback, BOM skip.

import Testing
import Foundation
@testable import vreader

@Suite("TXTChapterIndexBuilder")
struct TXTChapterIndexBuilderTests {

    // MARK: - Helpers

    /// The first enabled rule (中文章节通用) for testing with CJK chapter patterns.
    private var chineseChapterRule: TXTTocRule {
        TXTTocRuleEngine.defaultRules.first(where: { $0.id == 1 })!
    }

    /// The English Chapter/Section/Part rule.
    private var englishChapterRule: TXTTocRule {
        TXTTocRuleEngine.defaultRules.first(where: { $0.id == 3 })!
    }

    /// Helper to build UTF-8 data from a string.
    private func utf8Data(_ text: String) -> Data {
        Data(text.utf8)
    }

    // MARK: - Empty File

    @Test func testEmptyFile() {
        let data = Data()
        let index = TXTChapterIndexBuilder.build(
            data: data,
            encoding: .utf8,
            encodingName: "UTF-8",
            rule: nil
        )
        #expect(index.isEmpty)
        #expect(index.count == 0)
        #expect(index.totalBytes == 0)
        #expect(index.chapters.isEmpty)
    }

    // MARK: - Small File No Chapters (Synthetic)

    @Test func testSmallFileNoChapters() {
        // A file with no chapter patterns should produce synthetic chapters.
        let text = "This is a plain text file with no chapter headings.\n\nJust some paragraphs.\n\nMore content here."
        let data = utf8Data(text)
        let index = TXTChapterIndexBuilder.build(
            data: data,
            encoding: .utf8,
            encodingName: "UTF-8",
            rule: englishChapterRule
        )
        // Small file (< syntheticChapterSize) should produce exactly 1 synthetic chapter
        #expect(index.count >= 1)
        #expect(index.totalBytes == Int64(data.count))
        #expect(index.chapters.first?.startByte == 0)
        #expect(index.chapters.last?.endByte == Int64(data.count))
    }

    // MARK: - Small File With Chapters

    @Test func testSmallFileWithChapters() throws {
        let text = "第一章 开始\n这是第一章的内容，包含一些文字。\n\n第二章 发展\n这是第二章的内容，也包含一些文字。\n\n第三章 结局\n这是第三章的内容，故事结束。\n"
        let data = utf8Data(text)
        let index = TXTChapterIndexBuilder.build(
            data: data,
            encoding: .utf8,
            encodingName: "UTF-8",
            rule: chineseChapterRule
        )
        try #require(index.count == 3, "Expected 3 chapters, got \(index.count)")
        #expect(index.chapters[0].title.contains("第一章"))
        #expect(index.chapters[1].title.contains("第二章"))
        #expect(index.chapters[2].title.contains("第三章"))
        #expect(index.totalBytes == Int64(data.count))
        #expect(index.detectedEncoding == "UTF-8")
    }

    // MARK: - Chapter Bytes Contiguous

    @Test func testChapterBytesContiguous() throws {
        let text = "Chapter 1 The Beginning\nContent of chapter one.\n\nChapter 2 The Middle\nContent of chapter two.\n\nChapter 3 The End\nContent of chapter three.\n"
        let data = utf8Data(text)
        let index = TXTChapterIndexBuilder.build(
            data: data,
            encoding: .utf8,
            encodingName: "UTF-8",
            rule: englishChapterRule
        )
        try #require(index.count == 3)
        // Verify contiguity: each chapter's endByte == next chapter's startByte
        for i in 0..<(index.count - 1) {
            #expect(
                index.chapters[i].endByte == index.chapters[i + 1].startByte,
                "Chapter \(i) endByte (\(index.chapters[i].endByte)) != Chapter \(i+1) startByte (\(index.chapters[i+1].startByte))"
            )
        }
    }

    // MARK: - Block Boundary Split

    @Test func testBlockBoundarySplit() throws {
        // Create a file > 512KB (bufferSize) with chapters on both sides of the boundary.
        let chapterContent = String(repeating: "A", count: 200_000) + "\n"
        let text = "Chapter 1 First\n" + chapterContent +
                   "Chapter 2 Second\n" + chapterContent +
                   "Chapter 3 Third\n" + chapterContent
        let data = utf8Data(text)
        #expect(data.count > TXTChapterIndexBuilder.bufferSize,
                "Test data must exceed buffer size")

        let index = TXTChapterIndexBuilder.build(
            data: data,
            encoding: .utf8,
            encodingName: "UTF-8",
            rule: englishChapterRule
        )
        try #require(index.count == 3, "Expected 3 chapters across block boundaries, got \(index.count)")
        #expect(index.chapters[0].title.contains("Chapter 1"))
        #expect(index.chapters[1].title.contains("Chapter 2"))
        #expect(index.chapters[2].title.contains("Chapter 3"))
        // Last chapter must extend to EOF
        #expect(index.chapters.last?.endByte == Int64(data.count))
    }

    // MARK: - Synthetic Chapters at Paragraphs

    @Test func testSyntheticChaptersAtParagraphs() {
        // Create a file > syntheticChapterSize with \n\n paragraph breaks but no chapter headings.
        var text = ""
        // Build ~120KB of content with paragraph breaks every ~5KB
        for i in 0..<24 {
            text += "Paragraph block \(i).\n"
            text += String(repeating: "x", count: 5000)
            text += "\n\n"
        }
        let data = utf8Data(text)
        #expect(data.count > TXTChapterIndexBuilder.syntheticChapterSize)

        let index = TXTChapterIndexBuilder.build(
            data: data,
            encoding: .utf8,
            encodingName: "UTF-8",
            rule: nil  // no rule → synthetic
        )
        // Should have multiple synthetic chapters
        #expect(index.count >= 2, "Expected multiple synthetic chapters, got \(index.count)")
        // First chapter starts at 0
        #expect(index.chapters.first?.startByte == 0)
        // Last chapter ends at EOF
        #expect(index.chapters.last?.endByte == Int64(data.count))
        // All chapters should be contiguous
        for i in 0..<(index.count - 1) {
            #expect(index.chapters[i].endByte == index.chapters[i + 1].startByte)
        }
    }

    // MARK: - CJK Encoding (GBK)

    @Test func testCJKEncoding() throws {
        let text = "第一章 标题\n这是第一章的内容。\n\n第二章 标题\n这是第二章的内容。\n\n第三章 标题\n这是第三章的内容。\n"
        let gbkEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        guard let data = text.data(using: gbkEncoding) else {
            Issue.record("Could not encode test string as GBK")
            return
        }
        let index = TXTChapterIndexBuilder.build(
            data: data,
            encoding: gbkEncoding,
            encodingName: "GBK",
            rule: chineseChapterRule
        )
        try #require(index.count == 3, "Expected 3 chapters in GBK data, got \(index.count)")
        #expect(index.detectedEncoding == "GBK")
        #expect(index.chapters[0].title.contains("第一章"))
        #expect(index.totalBytes == Int64(data.count))
    }

    // MARK: - Last Chapter Extends to EOF

    @Test func testLastChapterExtendsToEOF() throws {
        let text = "Chapter 1 Intro\nSome content for chapter 1.\n\nChapter 2 Body\nSome content for chapter 2. This is the last chapter.\n"
        let data = utf8Data(text)
        let index = TXTChapterIndexBuilder.build(
            data: data,
            encoding: .utf8,
            encodingName: "UTF-8",
            rule: englishChapterRule
        )
        try #require(index.count == 2)
        #expect(index.chapters.last?.endByte == Int64(data.count),
                "Last chapter endByte (\(index.chapters.last?.endByte ?? -1)) should equal data.count (\(data.count))")
    }

    // MARK: - Single Chapter Match (Fallback to Synthetic)

    @Test func testSingleChapterMatch() {
        // Only one chapter match — needs >= 2, so should fall back to synthetic.
        var text = "Chapter 1 The Only One\n"
        text += String(repeating: "Content. ", count: 10_000) // ~90KB
        let data = utf8Data(text)
        let index = TXTChapterIndexBuilder.build(
            data: data,
            encoding: .utf8,
            encodingName: "UTF-8",
            rule: englishChapterRule
        )
        // With only 1 regex match, should fall back to synthetic chapters
        // The result should still cover the entire file
        #expect(index.chapters.first?.startByte == 0)
        #expect(index.chapters.last?.endByte == Int64(data.count))
    }

    // MARK: - UTF-8 BOM

    @Test func testUTF8BOM() throws {
        let text = "Chapter 1 After BOM\nContent here.\n\nChapter 2 Second\nMore content."
        var data = Data([0xEF, 0xBB, 0xBF]) // UTF-8 BOM
        data.append(Data(text.utf8))

        let index = TXTChapterIndexBuilder.build(
            data: data,
            encoding: .utf8,
            encodingName: "UTF-8",
            rule: englishChapterRule
        )
        try #require(index.count == 2, "Expected 2 chapters after BOM skip, got \(index.count)")
        // First chapter should start after the BOM (byte 3), not at 0
        #expect(index.chapters.first?.startByte == 3,
                "First chapter should start after 3-byte BOM, got \(index.chapters.first?.startByte ?? -1)")
        #expect(index.chapters.last?.endByte == Int64(data.count))
    }

    // MARK: - No Rule Provided, Small File

    @Test func testNoRuleSmallFile() throws {
        let text = "Just a small file.\n\nWith two paragraphs."
        let data = utf8Data(text)
        let index = TXTChapterIndexBuilder.build(
            data: data,
            encoding: .utf8,
            encodingName: "UTF-8",
            rule: nil
        )
        // Small file with no rule should produce exactly 1 chapter covering everything
        try #require(index.count == 1)
        #expect(index.chapters[0].startByte == 0)
        #expect(index.chapters[0].endByte == Int64(data.count))
    }
}
