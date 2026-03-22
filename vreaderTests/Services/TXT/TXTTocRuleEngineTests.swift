// Purpose: Tests for TXTTocRuleEngine — rule detection and TOC extraction logic.

import Testing
import Foundation
@testable import vreader

@Suite("TXTTocRuleEngine")
struct TXTTocRuleEngineTests {

    // MARK: - Test Helpers

    private let testFingerprint = DocumentFingerprint(
        contentSHA256: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
        fileByteCount: 500,
        format: .txt
    )

    /// Body text long enough to not match any chapter rule (>30 chars).
    private let bodyText = "这是一段足够长的内容，用来模拟真实小说的段落内容，不会被任何章节规则匹配到。"

    // MARK: - Default Rules

    @Test("default rules are non-empty")
    func defaultRulesExist() {
        #expect(!TXTTocRuleEngine.defaultRules.isEmpty)
    }

    @Test("default rules have 25 total entries")
    func defaultRulesCount() {
        #expect(TXTTocRuleEngine.defaultRules.count == 25)
    }

    @Test("14 rules are enabled by default (bug #83: broadened)")
    func enabledRulesCount() {
        let enabled = TXTTocRuleEngine.defaultRules.filter(\.enabled)
        #expect(enabled.count == 14)
    }

    @Test("each rule has unique ID")
    func uniqueIds() {
        let ids = TXTTocRuleEngine.defaultRules.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("each rule has non-empty name and pattern")
    func rulesHaveNameAndPattern() {
        for rule in TXTTocRuleEngine.defaultRules {
            #expect(!rule.name.isEmpty, "Rule \(rule.id) has empty name")
            #expect(!rule.rule.isEmpty, "Rule \(rule.id) has empty pattern")
        }
    }

    // MARK: - detectBestRule

    @Test("detectBestRule returns nil for plain text")
    func detectBestRule_noMatch() {
        let text = "普通文本，没有章节标记在这段文字里面。\n就是简单的长文字描述而已没有更多的内容了。"
        let result = TXTTocRuleEngine.detectBestRule(
            text: text,
            rules: TXTTocRuleEngine.defaultRules
        )
        #expect(result == nil)
    }

    @Test("detectBestRule finds Chinese chapter rule")
    func detectBestRule_chineseChapter() {
        let text = """
        第一章 开始
        \(bodyText)
        第二章 发展
        \(bodyText)
        第三章 高潮
        \(bodyText)
        """
        let result = TXTTocRuleEngine.detectBestRule(
            text: text,
            rules: TXTTocRuleEngine.defaultRules
        )
        #expect(result != nil)
    }

    @Test("detectBestRule only considers enabled rules")
    func detectBestRule_onlyEnabled() {
        let text = "第一章 标题\n\(bodyText)\n第二章 标题\n\(bodyText)"
        // Disable all rules
        let disabledRules = TXTTocRuleEngine.defaultRules.map { rule in
            var r = rule
            r.enabled = false
            return r
        }
        let result = TXTTocRuleEngine.detectBestRule(
            text: text,
            rules: disabledRules
        )
        #expect(result == nil)
    }

    @Test("detectBestRule returns nil for empty text")
    func detectBestRule_emptyText() {
        let result = TXTTocRuleEngine.detectBestRule(
            text: "",
            rules: TXTTocRuleEngine.defaultRules
        )
        #expect(result == nil)
    }

    // MARK: - extractTOC

    @Test("extractTOC returns empty for no matches")
    func extractTOC_noMatches() {
        let rule = TXTTocRuleEngine.defaultRules.first!
        let entries = TXTTocRuleEngine.extractTOC(
            text: "没有匹配的文本，这一行足够长，不会被任何规则匹配到的。",
            rule: rule,
            fingerprint: testFingerprint
        )
        #expect(entries.isEmpty)
    }

    @Test("extractTOC returns entries with correct titles")
    func extractTOC_correctTitles() {
        // Find the Chinese chapter rule (should be the first enabled one)
        guard let rule = TXTTocRuleEngine.defaultRules.first(where: {
            $0.enabled && $0.rule.contains("章")
        }) else {
            Issue.record("No Chinese chapter rule found")
            return
        }

        let text = "\(bodyText)\n第一章 黎明\n\(bodyText)\n第二章 黄昏\n\(bodyText)"
        let entries = TXTTocRuleEngine.extractTOC(
            text: text,
            rule: rule,
            fingerprint: testFingerprint
        )

        #expect(entries.count == 2)
        #expect(entries[0].title == "第一章 黎明")
        #expect(entries[1].title == "第二章 黄昏")
    }

    @Test("extractTOC entries have correct UTF-16 offsets")
    func extractTOC_correctOffsets() {
        guard let rule = TXTTocRuleEngine.defaultRules.first(where: {
            $0.enabled && $0.rule.contains("章")
        }) else {
            Issue.record("No Chinese chapter rule found")
            return
        }

        let preamble = "AAAA"
        let chapterOne = "第一章 AB"  // 6 UTF-16 code units
        let body = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
        let text = "\(preamble)\n\(chapterOne)\n\(body)\n第二章 CD"
        let entries = TXTTocRuleEngine.extractTOC(
            text: text,
            rule: rule,
            fingerprint: testFingerprint
        )

        #expect(entries.count == 2)
        let firstOffset = preamble.utf16.count + 1 // "AAAA" + \n
        #expect(entries[0].locator.charOffsetUTF16 == firstOffset)
        let secondOffset = firstOffset + chapterOne.utf16.count + 1 + body.utf16.count + 1
        #expect(entries[1].locator.charOffsetUTF16 == secondOffset)
    }

    @Test("extractTOC entries have sequential IDs")
    func extractTOC_sequentialIds() {
        guard let rule = TXTTocRuleEngine.defaultRules.first(where: {
            $0.enabled && $0.rule.contains("章")
        }) else {
            Issue.record("No Chinese chapter rule found")
            return
        }

        let text = "第一章 甲\n\(bodyText)\n第二章 乙\n\(bodyText)\n第三章 丙"
        let entries = TXTTocRuleEngine.extractTOC(
            text: text,
            rule: rule,
            fingerprint: testFingerprint
        )

        #expect(entries.count == 3)
        let ids = Set(entries.map(\.id))
        #expect(ids.count == 3)
    }

    @Test("extractTOC trims matched line whitespace")
    func extractTOC_trimsWhitespace() {
        guard let rule = TXTTocRuleEngine.defaultRules.first(where: {
            $0.enabled && $0.rule.contains("章")
        }) else {
            Issue.record("No Chinese chapter rule found")
            return
        }

        let text = "\(bodyText)\n  第一章 带空格  \n\(bodyText)\n  第二章 又来  \n\(bodyText)"
        let entries = TXTTocRuleEngine.extractTOC(
            text: text,
            rule: rule,
            fingerprint: testFingerprint
        )

        #expect(entries.count == 2)
        let title = entries[0].title
        #expect(!title.hasPrefix(" "))
        #expect(!title.hasSuffix(" "))
    }

    // MARK: - TXTTocRule Model

    @Test("TXTTocRule is Identifiable by id")
    func ruleIsIdentifiable() {
        let rule = TXTTocRule(
            id: 42,
            enabled: true,
            name: "Test",
            rule: ".*",
            example: "test",
            serialNumber: 1
        )
        #expect(rule.id == 42)
    }

    @Test("TXTTocRule is Codable")
    func ruleIsCodable() throws {
        let rule = TXTTocRule(
            id: 1,
            enabled: true,
            name: "Test Rule",
            rule: "^第.+章",
            example: "第一章 标题",
            serialNumber: 1
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(TXTTocRule.self, from: data)
        #expect(decoded.id == rule.id)
        #expect(decoded.name == rule.name)
        #expect(decoded.rule == rule.rule)
        #expect(decoded.enabled == rule.enabled)
    }

    // MARK: - Sampling Limit

    @Test("detectBestRule samples only first 512KB of text")
    func detectBestRule_samplingLimit() {
        // Create text > 512KB with chapters only after 512KB.
        // Each char of the padding is a CJK char = 2 bytes UTF-8 = 1 UTF-16 code unit.
        // 512KB of UTF-16 = 512*1024 = 524288 code units.
        // We need more than that in padding.
        let paddingLine = String(repeating: "啊", count: 1000) + "\n"
        // 1001 UTF-16 units per line, need ~524 lines
        let padding = String(repeating: paddingLine, count: 530)
        let text = padding + "第一章 标题\n第二章 继续\n第三章 结束"

        #expect(text.utf16.count > TXTTocRuleEngine.sampleSizeUTF16,
                "Test text must exceed sample limit")

        let result = TXTTocRuleEngine.detectBestRule(
            text: text,
            rules: TXTTocRuleEngine.defaultRules
        )
        // Chapters are after 512KB, so detectBestRule shouldn't find them
        #expect(result == nil)
    }
}
