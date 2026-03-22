// Purpose: Tests for TOCBuilder.forTXT — TXT chapter detection using Legado-ported rules.

import Testing
import Foundation
@testable import vreader

@Suite("TOCBuilder.forTXT")
struct TOCBuilderTXTTests {

    // MARK: - Test Helpers

    /// Creates a test fingerprint for TXT format.
    private let testFingerprint = DocumentFingerprint(
        contentSHA256: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
        fileByteCount: 500,
        format: .txt
    )

    /// Body text long enough to not match any chapter rule (>30 chars).
    private let bodyText = "这是一段足够长的内容，用来模拟真实小说的段落内容，不会被任何章节规则匹配到。"

    // MARK: - Chinese Chapter Patterns

    @Test("detects 第一章 标题")
    func chineseChapter_diYiZhang() {
        let text = "\(bodyText)\n第一章 黎明破晓\n\(bodyText)\n第二章 日落黄昏\n\(bodyText)"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "第一章 黎明破晓")
        #expect(entries[0].level == 0)
    }

    @Test("detects large Chinese numerals: 第三百九十二章")
    func chineseChapter_diSanBaiJiu() {
        // Need at least 2 matches for auto-detect confidence
        let text = "\(bodyText)\n第三百九十二章 风云再起\n\(bodyText)\n第三百九十三章 后续\n\(bodyText)"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "第三百九十二章 风云再起")
    }

    @Test("detects 卷五 开源盛世")
    func chineseVolume_juanWu() {
        // Need 2 matches for detection threshold
        let text = "\(bodyText)\n卷五 开源盛世\n\(bodyText)\n卷六 新的征程\n\(bodyText)"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "卷五 开源盛世")
    }

    // MARK: - English Chapter Patterns

    @Test("detects Chapter N Title")
    func englishChapter() {
        let text = "Prologue text that is long enough to avoid matching.\nChapter 1 The Beginning\nSome content that fills the page nicely.\nChapter 2 The Middle\nMore content follows."
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "Chapter 1 The Beginning")
        #expect(entries[1].title == "Chapter 2 The Middle")
    }

    // MARK: - Numbered Heading Patterns

    @Test("detects 1、这个标题")
    func numberedHeading() {
        let text = "\(bodyText)\n1、这个标题\n\(bodyText)\n2、第二个标题\n\(bodyText)"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "1、这个标题")
        #expect(entries[1].title == "2、第二个标题")
    }

    // MARK: - Special Symbol Patterns

    @Test("detects 【第一章 标题】")
    func specialSymbol_bracket() {
        let text = "\(bodyText)\n【第一章 标题】\n\(bodyText)\n【第二章 继续】\n\(bodyText)"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "【第一章 标题】")
    }

    @Test("detects ☆、标题")
    func specialSymbol_star() {
        let text = "\(bodyText)\n☆、第一个故事\n\(bodyText)\n☆、第二个故事\n\(bodyText)"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "☆、第一个故事")
        #expect(entries[1].title == "☆、第二个故事")
    }

    // MARK: - No Match / Edge Cases

    @Test("plain text with no chapter patterns returns empty")
    func noMatchReturnsEmpty() {
        let text = "这是一段普通文本，没有任何章节标记在里面。\n也没有数字开头的行或者特殊符号。\n就是一些非常普通的话而已，什么也没有。"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.isEmpty)
    }

    @Test("empty text returns empty array")
    func emptyText_returnsEmpty() {
        let entries = TOCBuilder.forTXT(text: "", fingerprint: testFingerprint)

        #expect(entries.isEmpty)
    }

    // MARK: - Auto-detect Best Rule

    @Test("auto-detects best rule from sample text")
    func autoDetectBestRule() {
        let text = """
        \(bodyText)
        第一章 起始
        \(bodyText)
        第二章 发展
        \(bodyText)
        第三章 高潮
        \(bodyText)
        """
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 3)
        #expect(entries[0].title == "第一章 起始")
        #expect(entries[1].title == "第二章 发展")
        #expect(entries[2].title == "第三章 高潮")
    }

    @Test("ambiguous text picks rule with most matches")
    func multipleRulesMatch_picksBest() {
        // This text has both numbered patterns (1、) and Chinese chapter patterns (第X章).
        // The Chinese chapter pattern should win because it has more matches.
        let text = """
        1、简介
        第一章 开端
        \(bodyText)
        第二章 中段
        \(bodyText)
        第三章 结局
        \(bodyText)
        """
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        // Should detect 3 Chinese chapters (best rule) rather than 1 numbered heading
        #expect(entries.count == 3)
        #expect(entries[0].title == "第一章 开端")
    }

    // MARK: - Offset Verification

    @Test("chapter UTF-16 offsets are correct for navigation")
    func chapterOffsets_correct() {
        let preamble = "AAAA"
        let text = "\(preamble)\n第一章 标题\n\(bodyText)\n第二章 后续\n\(bodyText)"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        // preamble(4) + \n(1) = 5
        #expect(entries[0].locator.charOffsetUTF16 == preamble.utf16.count + 1)
    }

    @Test("multiple chapter offsets are sequential and correct")
    func multipleChapterOffsets() {
        let chapterOne = "第一章 AB"  // 6 UTF-16 code units
        let body = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        let text = "\(chapterOne)\n\(body)\n第二章 EF"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].locator.charOffsetUTF16 == 0)
        // chapterOne(6) + \n(1) + body(36) + \n(1) = 44
        let expectedOffset = chapterOne.utf16.count + 1 + body.utf16.count + 1
        #expect(entries[1].locator.charOffsetUTF16 == expectedOffset)
    }

    // MARK: - CJK Numerals

    @Test("all CJK numeral forms work")
    func cjkNumerals_allForms() {
        // Test multiple CJK numeral forms in chapter numbers
        let text = """
        第零章 序
        \(bodyText)
        第壹章 壹的故事
        \(bodyText)
        第拾章 大数的故事
        \(bodyText)
        """
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 3)
        #expect(entries[0].title == "第零章 序")
        #expect(entries[1].title == "第壹章 壹的故事")
        #expect(entries[2].title == "第拾章 大数的故事")
    }

    // MARK: - Locator Validation

    @Test("entries have valid locators with correct fingerprint")
    func entriesHaveValidLocators() {
        let text = "第一章 测试\n\(bodyText)\n第二章 继续\n\(bodyText)"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].locator.bookFingerprint == testFingerprint)
    }

    @Test("sequential entries have distinct IDs")
    func sequentialEntriesHaveDistinctIds() {
        let text = "第一章 甲\n\(bodyText)\n第二章 乙\n\(bodyText)\n第三章 丙"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 3)
        let ids = Set(entries.map(\.id))
        #expect(ids.count == 3)
    }

    // MARK: - Special Chapter Keywords

    @Test("detects 序章, 楔子, 终章, 后记, 尾声, 番外")
    func specialKeywords() {
        let text = """
        序章
        \(bodyText)
        楔子
        \(bodyText)
        终章
        \(bodyText)
        后记
        \(bodyText)
        尾声
        \(bodyText)
        番外
        \(bodyText)
        """
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 6)
        #expect(entries[0].title == "序章")
        #expect(entries[1].title == "楔子")
        #expect(entries[2].title == "终章")
        #expect(entries[3].title == "后记")
        #expect(entries[4].title == "尾声")
        #expect(entries[5].title == "番外")
    }

    // MARK: - Arabic Numeral Chapter

    @Test("detects 第1章 with Arabic numeral")
    func arabicNumeralChapter() {
        let text = "\(bodyText)\n第1章 开始\n\(bodyText)\n第20章 继续\n\(bodyText)"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title == "第1章 开始")
        #expect(entries[1].title == "第20章 继续")
    }

    // MARK: - Section / Part / Episode (English)

    @Test("detects Section, Part, Episode")
    func englishVariants() {
        let text = """
        Some introductory text that spans multiple words and is not a chapter heading.
        Section 1 Introduction
        Content text that is long enough to not be matched by any rule at all.
        Part 2 Main Body
        More content text filling up the space between chapter headings here.
        Episode 3 Finale
        Final content text goes here with lots of words to be safe from matching.
        """
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 3)
        #expect(entries[0].title == "Section 1 Introduction")
        #expect(entries[1].title == "Part 2 Main Body")
        #expect(entries[2].title == "Episode 3 Finale")
    }

    // MARK: - Leading Whitespace Tolerance

    @Test("detects chapters with up to 4 leading spaces")
    func leadingWhitespace() {
        let text = "\(bodyText)\n    第一章 缩进章节\n\(bodyText)\n    第二章 又一个\n\(bodyText)"
        let entries = TOCBuilder.forTXT(text: text, fingerprint: testFingerprint)

        #expect(entries.count == 2)
        #expect(entries[0].title.contains("第一章"))
    }
}
