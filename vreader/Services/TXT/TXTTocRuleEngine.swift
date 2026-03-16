// Purpose: TXT chapter detection engine with 25 Legado-ported regex rules.
// Auto-detects the best matching rule by sampling text, then extracts TOC entries.
//
// Key decisions:
// - Rules ported verbatim from Legado's txtTocRule.json (44.8k stars, battle-tested).
// - Auto-detection samples first 512KB (UTF-16) to avoid scanning huge files.
// - Best rule = enabled rule with most matches in sample.
// - Extraction uses NSRegularExpression with .anchorsMatchLines for ^ and $ matching.
// - TOC titles are the full matched line, trimmed of whitespace.
// - UTF-16 offsets used for locator compatibility with TextKit.
//
// @coordinates-with: TXTTocRule.swift, TOCBuilder.swift, LocatorFactory.swift

import Foundation

/// Engine for detecting chapters in TXT files using configurable regex rules.
enum TXTTocRuleEngine {

    // MARK: - Constants

    /// Maximum number of UTF-16 code units to sample for auto-detection.
    static let sampleSizeUTF16 = 512 * 1024  // 512KB worth of UTF-16

    // MARK: - Default Rules (Legado Port)

    /// All 25 rules ported from Legado's txtTocRule.json.
    /// 8 are enabled by default (matching Legado's defaults).
    static let defaultRules: [TXTTocRule] = Self.buildDefaultRules()

    // MARK: - Auto-Detection

    /// Finds the best matching rule by sampling the first 512KB of text.
    /// Returns nil if no enabled rule matches at least 2 times.
    /// - Parameters:
    ///   - text: Full text content.
    ///   - rules: Rules to try (typically `defaultRules`).
    /// - Returns: The rule with the most matches, or nil.
    static func detectBestRule(
        text: String,
        rules: [TXTTocRule]
    ) -> TXTTocRule? {
        guard !text.isEmpty else { return nil }

        // Sample first 512KB of text
        let sample: String
        if text.utf16.count > sampleSizeUTF16 {
            let endIndex = String.Index(
                utf16Offset: sampleSizeUTF16, in: text
            )
            sample = String(text[text.startIndex..<endIndex])
        } else {
            sample = text
        }

        let enabledRules = rules.filter(\.enabled)
        guard !enabledRules.isEmpty else { return nil }

        var bestRule: TXTTocRule?
        var bestCount = 0

        for rule in enabledRules {
            guard let regex = try? NSRegularExpression(
                pattern: rule.rule,
                options: [.anchorsMatchLines]
            ) else { continue }

            let range = NSRange(sample.startIndex..., in: sample)
            let count = regex.numberOfMatches(in: sample, range: range)

            if count > bestCount {
                bestCount = count
                bestRule = rule
            }
        }

        // Require at least 2 matches for confidence
        return bestCount >= 2 ? bestRule : nil
    }

    // MARK: - TOC Extraction

    /// Extracts TOC entries from text using a specific rule.
    /// - Parameters:
    ///   - text: Full text content.
    ///   - rule: The rule to apply.
    ///   - fingerprint: Document fingerprint for locator creation.
    /// - Returns: Array of TOCEntry in document order.
    static func extractTOC(
        text: String,
        rule: TXTTocRule,
        fingerprint: DocumentFingerprint
    ) -> [TOCEntry] {
        guard !text.isEmpty else { return [] }

        guard let regex = try? NSRegularExpression(
            pattern: rule.rule,
            options: [.anchorsMatchLines]
        ) else { return [] }

        let nsString = text as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: text, range: fullRange)

        var entries: [TOCEntry] = []

        for (index, match) in matches.enumerated() {
            let matchRange = match.range
            guard matchRange.location != NSNotFound else { continue }

            let title = nsString.substring(with: matchRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let utf16Offset = matchRange.location

            let locator = LocatorFactory.txtPosition(
                fingerprint: fingerprint,
                charOffsetUTF16: utf16Offset,
                sourceText: text
            )
            guard let locator else { continue }

            entries.append(TOCEntry(
                title: title,
                level: 0,
                locator: locator,
                sequenceIndex: index
            ))
        }

        return entries
    }
}

// MARK: - Rule Definitions (Private)

private extension TXTTocRuleEngine {

    /// Builds the 25 default rules ported from Legado's txtTocRule.json.
    /// Rules are ordered by serialNumber. 8 are enabled by default.
    // swiftlint:disable:next function_body_length
    static func buildDefaultRules() -> [TXTTocRule] {
        [
            // --- Enabled by default (8 rules) ---

            TXTTocRule(
                id: 1,
                enabled: true,
                name: "中文章节（通用）",
                rule: #"^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$"#,
                example: "第一章 标题",
                serialNumber: 1
            ),
            TXTTocRule(
                id: 2,
                enabled: true,
                name: "中文数字章节",
                rule: #"^[ 　\t]{0,4}[第（\(]?\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}[章节卷集部篇回话]\s?.{0,30}$"#,
                example: "第123章 标题",
                serialNumber: 2
            ),
            TXTTocRule(
                id: 3,
                enabled: true,
                name: "英文Chapter/Section/Part",
                rule: #"^[ 　\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|[Ee]pisode)\s{0,4}\d{1,4}.{0,30}$"#,
                example: "Chapter 1 Title",
                serialNumber: 3
            ),
            TXTTocRule(
                id: 4,
                enabled: true,
                name: "数字+标点标题",
                rule: #"^[ 　\t]{0,4}\d{1,5}[：:,.， 、_—\-].{1,30}$"#,
                example: "1、这个标题",
                serialNumber: 4
            ),
            TXTTocRule(
                id: 5,
                enabled: true,
                name: "特殊符号·章节",
                rule: #"^[ 　\t]{0,4}[【\[☆★●◆◇○◎□■△▲※卐].{1,30}$"#,
                example: "【第一章 标题】",
                serialNumber: 5
            ),
            TXTTocRule(
                id: 6,
                enabled: true,
                name: "正文+标题",
                rule: #"^[ 　\t]{0,4}正文\s.{0,20}$"#,
                example: "正文 第一章",
                serialNumber: 6
            ),
            TXTTocRule(
                id: 7,
                enabled: true,
                name: "中文卷/篇/部/集",
                rule: #"^[ 　\t]{0,4}(?:卷|篇|部|集)\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+.{0,30}$"#,
                example: "卷五 开源盛世",
                serialNumber: 7
            ),
            TXTTocRule(
                id: 8,
                enabled: true,
                name: "星号标题",
                rule: #"^[ 　\t]{0,4}[☆★].{1,30}$"#,
                example: "☆、第一个故事",
                serialNumber: 8
            ),

            // --- Disabled by default (17 rules) ---

            TXTTocRule(
                id: 9,
                enabled: false,
                name: "Volume + Number",
                rule: #"^[ 　\t]{0,4}[Vv]ol(?:ume)?\s{0,4}\d{1,4}.{0,30}$"#,
                example: "Volume 1 Title",
                serialNumber: 9
            ),
            TXTTocRule(
                id: 10,
                enabled: false,
                name: "Book + Number",
                rule: #"^[ 　\t]{0,4}[Bb]ook\s{0,4}\d{1,4}.{0,30}$"#,
                example: "Book 1 Title",
                serialNumber: 10
            ),
            TXTTocRule(
                id: 11,
                enabled: false,
                name: "Act + Number",
                rule: #"^[ 　\t]{0,4}[Aa]ct\s{0,4}\d{1,4}.{0,30}$"#,
                example: "Act 1 Title",
                serialNumber: 11
            ),
            TXTTocRule(
                id: 12,
                enabled: false,
                name: "Scene + Number",
                rule: #"^[ 　\t]{0,4}[Ss]cene\s{0,4}\d{1,4}.{0,30}$"#,
                example: "Scene 1 Title",
                serialNumber: 12
            ),
            TXTTocRule(
                id: 13,
                enabled: false,
                name: "数字序号（圆括号）",
                rule: #"^[ 　\t]{0,4}[\(（]\d{1,5}[\)）].{1,30}$"#,
                example: "(1) 标题",
                serialNumber: 13
            ),
            TXTTocRule(
                id: 14,
                enabled: false,
                name: "数字序号（点号）",
                rule: #"^[ 　\t]{0,4}\d{1,5}\..{1,30}$"#,
                example: "1.标题",
                serialNumber: 14
            ),
            TXTTocRule(
                id: 15,
                enabled: false,
                name: "罗马数字章节",
                rule: #"^[ 　\t]{0,4}(?:I{1,3}|IV|VI{0,3}|IX|XI{0,3}|XIV|XVI{0,3}|XIX|XXI{0,3})[.、：:\s].{0,30}$"#,
                example: "III. 标题",
                serialNumber: 15
            ),
            TXTTocRule(
                id: 16,
                enabled: false,
                name: "天干地支",
                rule: #"^[ 　\t]{0,4}[甲乙丙丁戊己庚辛壬癸][.、：:\s].{0,30}$"#,
                example: "甲、标题",
                serialNumber: 16
            ),
            TXTTocRule(
                id: 17,
                enabled: false,
                name: "全角数字章节",
                rule: #"^[ 　\t]{0,4}[０-９]{1,5}[.、：:\s].{0,30}$"#,
                example: "０１、标题",
                serialNumber: 17
            ),
            TXTTocRule(
                id: 18,
                enabled: false,
                name: "圆圈数字",
                rule: #"^[ 　\t]{0,4}[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳].{0,30}$"#,
                example: "① 标题",
                serialNumber: 18
            ),
            TXTTocRule(
                id: 19,
                enabled: false,
                name: "括号+中文数字",
                rule: #"^[ 　\t]{0,4}[（\(][零一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+[）\)].{0,30}$"#,
                example: "(一) 标题",
                serialNumber: 19
            ),
            TXTTocRule(
                id: 20,
                enabled: false,
                name: "Prologue/Epilogue/Interlude",
                rule: #"^[ 　\t]{0,4}(?:[Pp]rologue|[Ee]pilogue|[Ii]nterlude|[Pp]reface|[Ff]oreword|[Aa]fterword|[Ii]ntroduction|[Cc]onclusion).{0,30}$"#,
                example: "Prologue",
                serialNumber: 20
            ),
            TXTTocRule(
                id: 21,
                enabled: false,
                name: "中文括号标题",
                rule: #"^[ 　\t]{0,4}〔.{1,20}〕\s{0,4}$"#,
                example: "〔一〕",
                serialNumber: 21
            ),
            TXTTocRule(
                id: 22,
                enabled: false,
                name: "日文章节",
                rule: #"^[ 　\t]{0,4}第[\d〇零一二三四五六七八九十百千万]+?(?:章|節|巻|話|編).{0,30}$"#,
                example: "第一章 始まり",
                serialNumber: 22
            ),
            TXTTocRule(
                id: 23,
                enabled: false,
                name: "中文回/话",
                rule: #"^[ 　\t]{0,4}第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}[回话].{0,30}$"#,
                example: "第一回 标题",
                serialNumber: 23
            ),
            TXTTocRule(
                id: 24,
                enabled: false,
                name: "短线分隔章节",
                rule: #"^[ 　\t]{0,4}[—\-]{3,}.{0,30}$"#,
                example: "--- 章节标题",
                serialNumber: 24
            ),
            TXTTocRule(
                id: 25,
                enabled: false,
                name: "等号分隔章节",
                rule: #"^[ 　\t]{0,4}[=]{3,}.{0,30}$"#,
                example: "=== 章节标题",
                serialNumber: 25
            ),
        ]
    }
}
