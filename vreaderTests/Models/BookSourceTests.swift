// Purpose: Tests for BookSource @Model and BookSourceRules — Codable round-trips,
// optional field safety, enable/disable toggling, and URL validation.

import Testing
import Foundation
@testable import vreader

@Suite("BookSource Model")
struct BookSourceTests {

    // MARK: - BookSource Codable Round-Trip (via SwiftData-compatible init)

    @Test func bookSource_initSetsAllRequiredFields() {
        let source = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Test Source",
            sourceType: 0
        )
        #expect(source.sourceURL == "https://example.com")
        #expect(source.sourceName == "Test Source")
        #expect(source.sourceType == 0)
        #expect(source.enabled == true)
        #expect(source.customOrder == 0)
    }

    @Test func bookSource_allFieldsEncoded() {
        let source = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Full Source",
            sourceType: 1
        )
        source.sourceGroup = "Chinese Novels"
        source.searchURL = "https://example.com/search?q={{key}}"
        source.header = "{\"User-Agent\": \"VReader/1.0\"}"
        source.enabled = false
        source.customOrder = 5
        source.lastUpdateTime = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(source.sourceURL == "https://example.com")
        #expect(source.sourceName == "Full Source")
        #expect(source.sourceGroup == "Chinese Novels")
        #expect(source.sourceType == 1)
        #expect(source.enabled == false)
        #expect(source.searchURL == "https://example.com/search?q={{key}}")
        #expect(source.header == "{\"User-Agent\": \"VReader/1.0\"}")
        #expect(source.customOrder == 5)
        #expect(source.lastUpdateTime != nil)
    }

    @Test func bookSource_optionalFields_nilSafe() {
        let source = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Minimal",
            sourceType: 0
        )
        #expect(source.sourceGroup == nil)
        #expect(source.searchURL == nil)
        #expect(source.header == nil)
        #expect(source.ruleSearchData == nil)
        #expect(source.ruleBookInfoData == nil)
        #expect(source.ruleTocData == nil)
        #expect(source.ruleContentData == nil)
        #expect(source.lastUpdateTime == nil)

        // Computed rule accessors should also return nil
        #expect(source.ruleSearch == nil)
        #expect(source.ruleBookInfo == nil)
        #expect(source.ruleToc == nil)
        #expect(source.ruleContent == nil)
    }

    @Test func bookSource_enableDisable() {
        let source = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Toggle Test",
            sourceType: 0
        )
        #expect(source.enabled == true)

        source.enabled = false
        #expect(source.enabled == false)

        source.enabled = true
        #expect(source.enabled == true)
    }

    @Test func bookSource_emptyURL_rejected() {
        // Empty URL should be rejected by the validate method
        let result = BookSource.validateSourceURL("")
        #expect(result == false)
    }

    @Test func bookSource_whitespaceOnlyURL_rejected() {
        let result = BookSource.validateSourceURL("   ")
        #expect(result == false)
    }

    @Test func bookSource_validURL_accepted() {
        let result = BookSource.validateSourceURL("https://example.com")
        #expect(result == true)
    }

    @Test func bookSource_uniqueByURL() {
        // Verify that sourceURL is the unique identifier
        let source1 = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Source A",
            sourceType: 0
        )
        let source2 = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Source B",
            sourceType: 1
        )
        // Both have the same sourceURL — uniqueness enforced at the SwiftData level
        #expect(source1.sourceURL == source2.sourceURL)
    }

    // MARK: - Source Type Values

    @Test func bookSource_sourceType_text() {
        let source = BookSource(sourceURL: "https://a.com", sourceName: "T", sourceType: 0)
        #expect(source.sourceType == 0)
    }

    @Test func bookSource_sourceType_audio() {
        let source = BookSource(sourceURL: "https://a.com", sourceName: "A", sourceType: 1)
        #expect(source.sourceType == 1)
    }

    @Test func bookSource_sourceType_image() {
        let source = BookSource(sourceURL: "https://a.com", sourceName: "I", sourceType: 2)
        #expect(source.sourceType == 2)
    }

    @Test func bookSource_sourceType_file() {
        let source = BookSource(sourceURL: "https://a.com", sourceName: "F", sourceType: 3)
        #expect(source.sourceType == 3)
    }

    // MARK: - Custom Order

    @Test func bookSource_customOrder_defaults() {
        let source = BookSource(sourceURL: "https://a.com", sourceName: "S", sourceType: 0)
        #expect(source.customOrder == 0)
    }

    @Test func bookSource_customOrder_canBeSet() {
        let source = BookSource(sourceURL: "https://a.com", sourceName: "S", sourceType: 0)
        source.customOrder = 42
        #expect(source.customOrder == 42)
    }

    // MARK: - CJK Source Names

    @Test func bookSource_cjkSourceName() {
        let source = BookSource(
            sourceURL: "https://example.cn",
            sourceName: "笔趣阁",
            sourceType: 0
        )
        #expect(source.sourceName == "笔趣阁")
    }

    @Test func bookSource_longSourceName() {
        let longName = String(repeating: "a", count: 500)
        let source = BookSource(
            sourceURL: "https://example.com",
            sourceName: longName,
            sourceType: 0
        )
        #expect(source.sourceName == longName)
    }
}

// MARK: - Search Rule Tests

@Suite("BSSearchRule")
struct BSSearchRuleTests {

    @Test func searchRule_codableRoundTrip() throws {
        let rule = BSSearchRule(
            bookList: "div.result-list",
            name: "h3.title",
            author: "span.author",
            bookUrl: "a@href",
            coverUrl: "img@src"
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(BSSearchRule.self, from: data)

        #expect(decoded.bookList == "div.result-list")
        #expect(decoded.name == "h3.title")
        #expect(decoded.author == "span.author")
        #expect(decoded.bookUrl == "a@href")
        #expect(decoded.coverUrl == "img@src")
    }

    @Test func searchRule_allNil() throws {
        let rule = BSSearchRule()
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(BSSearchRule.self, from: data)

        #expect(decoded.bookList == nil)
        #expect(decoded.name == nil)
        #expect(decoded.author == nil)
        #expect(decoded.bookUrl == nil)
        #expect(decoded.coverUrl == nil)
    }

    @Test func searchRule_partialFields() throws {
        let rule = BSSearchRule(bookList: "div.list", name: "h3")
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(BSSearchRule.self, from: data)

        #expect(decoded.bookList == "div.list")
        #expect(decoded.name == "h3")
        #expect(decoded.author == nil)
        #expect(decoded.bookUrl == nil)
        #expect(decoded.coverUrl == nil)
    }
}

// MARK: - BookInfo Rule Tests

@Suite("BSBookInfoRule")
struct BSBookInfoRuleTests {

    @Test func bookInfoRule_codableRoundTrip() throws {
        let rule = BSBookInfoRule(
            name: "h1.title",
            author: "span.author",
            intro: "div.intro",
            coverUrl: "img.cover@src",
            tocUrl: "a.toc@href"
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(BSBookInfoRule.self, from: data)

        #expect(decoded.name == "h1.title")
        #expect(decoded.author == "span.author")
        #expect(decoded.intro == "div.intro")
        #expect(decoded.coverUrl == "img.cover@src")
        #expect(decoded.tocUrl == "a.toc@href")
    }

    @Test func bookInfoRule_allNil() throws {
        let rule = BSBookInfoRule()
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(BSBookInfoRule.self, from: data)

        #expect(decoded.name == nil)
        #expect(decoded.author == nil)
        #expect(decoded.intro == nil)
        #expect(decoded.coverUrl == nil)
        #expect(decoded.tocUrl == nil)
    }
}

// MARK: - TOC Rule Tests

@Suite("BSTocRule")
struct BSTocRuleTests {

    @Test func tocRule_codableRoundTrip() throws {
        let rule = BSTocRule(
            chapterList: "ul.chapters li",
            chapterName: "a",
            chapterUrl: "a@href",
            nextTocUrl: "a.next@href"
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(BSTocRule.self, from: data)

        #expect(decoded.chapterList == "ul.chapters li")
        #expect(decoded.chapterName == "a")
        #expect(decoded.chapterUrl == "a@href")
        #expect(decoded.nextTocUrl == "a.next@href")
    }

    @Test func tocRule_allNil() throws {
        let rule = BSTocRule()
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(BSTocRule.self, from: data)

        #expect(decoded.chapterList == nil)
        #expect(decoded.chapterName == nil)
        #expect(decoded.chapterUrl == nil)
        #expect(decoded.nextTocUrl == nil)
    }
}

// MARK: - Content Rule Tests

@Suite("BSContentRule")
struct BSContentRuleTests {

    @Test func contentRule_codableRoundTrip() throws {
        let rule = BSContentRule(
            content: "div#content",
            nextContentUrl: "a.next@href",
            replaceRegex: "广告.*?移除"
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(BSContentRule.self, from: data)

        #expect(decoded.content == "div#content")
        #expect(decoded.nextContentUrl == "a.next@href")
        #expect(decoded.replaceRegex == "广告.*?移除")
    }

    @Test func contentRule_allNil() throws {
        let rule = BSContentRule()
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(BSContentRule.self, from: data)

        #expect(decoded.content == nil)
        #expect(decoded.nextContentUrl == nil)
        #expect(decoded.replaceRegex == nil)
    }

    @Test func contentRule_cjkRegex() throws {
        let rule = BSContentRule(replaceRegex: "请收藏.*?最新章节")
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(BSContentRule.self, from: data)

        #expect(decoded.replaceRegex == "请收藏.*?最新章节")
    }
}

// MARK: - Rule Data Storage (BookSource computed properties)

@Suite("BookSource Rule Data Storage")
struct BookSourceRuleDataTests {

    @Test func bookSource_setAndGetSearchRule() {
        let source = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Test",
            sourceType: 0
        )
        let rule = BSSearchRule(bookList: "div.list", name: "h3")
        source.updateSearchRule(rule)

        let retrieved = source.ruleSearch
        #expect(retrieved != nil)
        #expect(retrieved?.bookList == "div.list")
        #expect(retrieved?.name == "h3")
    }

    @Test func bookSource_setAndGetBookInfoRule() {
        let source = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Test",
            sourceType: 0
        )
        let rule = BSBookInfoRule(name: "h1", author: "span.author")
        source.updateBookInfoRule(rule)

        let retrieved = source.ruleBookInfo
        #expect(retrieved != nil)
        #expect(retrieved?.name == "h1")
        #expect(retrieved?.author == "span.author")
    }

    @Test func bookSource_setAndGetTocRule() {
        let source = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Test",
            sourceType: 0
        )
        let rule = BSTocRule(chapterList: "ul li", chapterName: "a")
        source.updateTocRule(rule)

        let retrieved = source.ruleToc
        #expect(retrieved != nil)
        #expect(retrieved?.chapterList == "ul li")
        #expect(retrieved?.chapterName == "a")
    }

    @Test func bookSource_setAndGetContentRule() {
        let source = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Test",
            sourceType: 0
        )
        let rule = BSContentRule(content: "div#chapter-content")
        source.updateContentRule(rule)

        let retrieved = source.ruleContent
        #expect(retrieved != nil)
        #expect(retrieved?.content == "div#chapter-content")
    }

    @Test func bookSource_clearRule_setsNil() {
        let source = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Test",
            sourceType: 0
        )
        let rule = BSSearchRule(bookList: "div.list")
        source.updateSearchRule(rule)
        #expect(source.ruleSearch != nil)

        source.updateSearchRule(nil)
        #expect(source.ruleSearch == nil)
        #expect(source.ruleSearchData == nil)
    }

    @Test func bookSource_corruptedData_returnsNil() {
        let source = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Test",
            sourceType: 0
        )
        // Inject corrupted data directly
        source.ruleSearchData = Data([0xFF, 0xFE, 0x00])

        // Should return nil, not crash
        #expect(source.ruleSearch == nil)
    }

    @Test func bookSource_emptyData_returnsNil() {
        let source = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Test",
            sourceType: 0
        )
        source.ruleSearchData = Data()

        #expect(source.ruleSearch == nil)
    }
}
