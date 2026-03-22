// Purpose: Tests for LegadoImporter — import/export BookSource in Legado JSON format
// with compatibility classification (Full/Limited/Unsupported).
//
// @coordinates-with: LegadoImporter.swift, LegadoBookSourceDTO.swift, BookSource.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Test Helpers

/// Loads fixture JSON data from the test bundle.
private func loadFixture(_ name: String) throws -> Data {
    let bundle = Bundle(for: BundleToken.self)
    guard let url = bundle.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Fixtures/BookSource"
    ) else {
        // Fallback: try without subdirectory (flat bundle)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw LegadoImportError.invalidJSON
        }
        return try Data(contentsOf: url)
    }
    return try Data(contentsOf: url)
}

/// Anchor class for Bundle(for:) in test target.
private class BundleToken {}

// MARK: - Import Tests

@Suite("LegadoImporter — Import")
struct LegadoImporterImportTests {

    @Test func importSingleSource_createsBookSource() throws {
        let json = """
        {
            "bookSourceUrl": "https://www.example.com",
            "bookSourceName": "Example Source",
            "bookSourceType": 0,
            "enabled": true,
            "searchUrl": "https://www.example.com/search?q={{key}}",
            "header": "{\\"User-Agent\\": \\"Mozilla/5.0\\"}",
            "ruleSearch": {
                "bookList": "div.list",
                "name": "h3.title",
                "author": "span.author",
                "bookUrl": "a@href",
                "coverUrl": "img@src"
            },
            "ruleBookInfo": {
                "name": "h1.book-title",
                "author": "span.author",
                "intro": "div.intro",
                "coverUrl": "img@src",
                "tocUrl": "a.toc@href"
            },
            "ruleToc": {
                "chapterList": "ul.chapters li",
                "chapterName": "a",
                "chapterUrl": "a@href",
                "nextTocUrl": "a.next@href"
            },
            "ruleContent": {
                "content": "div#content",
                "nextContentUrl": "a.next@href",
                "replaceRegex": "广告.*?移除"
            },
            "bookSourceGroup": "Test Group",
            "customOrder": 3,
            "lastUpdateTime": 1700000000000
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        let source = sources[0]
        #expect(source.sourceURL == "https://www.example.com")
        #expect(source.sourceName == "Example Source")
        #expect(source.sourceType == 0)
        #expect(source.enabled == true)
        #expect(source.searchURL == "https://www.example.com/search?q={{key}}")
        #expect(source.header == "{\"User-Agent\": \"Mozilla/5.0\"}")
        #expect(source.sourceGroup == "Test Group")
        #expect(source.customOrder == 3)

        // Verify rules were decoded
        let searchRule = source.ruleSearch
        #expect(searchRule?.bookList == "div.list")
        #expect(searchRule?.name == "h3.title")
        #expect(searchRule?.author == "span.author")

        let bookInfoRule = source.ruleBookInfo
        #expect(bookInfoRule?.name == "h1.book-title")
        #expect(bookInfoRule?.tocUrl == "a.toc@href")

        let tocRule = source.ruleToc
        #expect(tocRule?.chapterList == "ul.chapters li")
        #expect(tocRule?.nextTocUrl == "a.next@href")

        let contentRule = source.ruleContent
        #expect(contentRule?.content == "div#content")
        #expect(contentRule?.replaceRegex == "广告.*?移除")
    }

    @Test func importMultipleSources_createsAll() throws {
        let json = """
        [
            {
                "bookSourceUrl": "https://source-a.com",
                "bookSourceName": "Source A",
                "bookSourceType": 0,
                "enabled": true
            },
            {
                "bookSourceUrl": "https://source-b.com",
                "bookSourceName": "Source B",
                "bookSourceType": 1,
                "enabled": false
            },
            {
                "bookSourceUrl": "https://source-c.com",
                "bookSourceName": "Source C",
                "bookSourceType": 0,
                "enabled": true
            }
        ]
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 3)
        #expect(sources[0].sourceURL == "https://source-a.com")
        #expect(sources[0].sourceName == "Source A")
        #expect(sources[1].sourceURL == "https://source-b.com")
        #expect(sources[1].sourceType == 1)
        #expect(sources[1].enabled == false)
        #expect(sources[2].sourceURL == "https://source-c.com")
    }

    @Test func importUnknownFields_ignored() throws {
        let json = """
        {
            "bookSourceUrl": "https://www.unknown.com",
            "bookSourceName": "Unknown Fields",
            "bookSourceType": 0,
            "enabled": true,
            "futureField1": "some value",
            "futureField2": 42,
            "futureNestedObject": { "key": "value" },
            "ruleSearch": {
                "bookList": "div.list",
                "name": "h3",
                "futureSearchField": "should be ignored"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].sourceURL == "https://www.unknown.com")
        #expect(sources[0].sourceName == "Unknown Fields")
        #expect(sources[0].ruleSearch?.bookList == "div.list")
    }

    @Test func importMissingOptionalFields_defaults() throws {
        let json = """
        {
            "bookSourceUrl": "https://www.minimal.com",
            "bookSourceName": "Minimal Source"
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        let source = sources[0]
        #expect(source.sourceURL == "https://www.minimal.com")
        #expect(source.sourceName == "Minimal Source")
        #expect(source.sourceType == 0) // default
        #expect(source.enabled == true) // default
        #expect(source.searchURL == nil)
        #expect(source.header == nil)
        #expect(source.sourceGroup == nil)
        #expect(source.ruleSearch == nil)
        #expect(source.ruleBookInfo == nil)
        #expect(source.ruleToc == nil)
        #expect(source.ruleContent == nil)
    }

    @Test func importDuplicateURL_skips() throws {
        let json = """
        [
            {
                "bookSourceUrl": "https://www.duplicate.com",
                "bookSourceName": "First",
                "bookSourceType": 0
            },
            {
                "bookSourceUrl": "https://www.duplicate.com",
                "bookSourceName": "Second (duplicate)",
                "bookSourceType": 0
            },
            {
                "bookSourceUrl": "https://www.unique.com",
                "bookSourceName": "Unique",
                "bookSourceType": 0
            }
        ]
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 2)
        #expect(sources[0].sourceURL == "https://www.duplicate.com")
        #expect(sources[0].sourceName == "First") // keeps first
        #expect(sources[1].sourceURL == "https://www.unique.com")
    }

    @Test func importInvalidJSON_returnsError() {
        let data = "not valid json".data(using: .utf8)!
        #expect(throws: LegadoImportError.self) {
            _ = try LegadoImporter.importSources(from: data)
        }
    }

    @Test func importEmptyArray_noOp() throws {
        let json = "[]"
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.isEmpty)
    }

    @Test func importAudioSource_typePreserved() throws {
        let json = """
        {
            "bookSourceUrl": "https://audio.example.com",
            "bookSourceName": "Audio Source",
            "bookSourceType": 1,
            "enabled": true
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].sourceType == 1)
    }
}

// MARK: - Export Tests

@Suite("LegadoImporter — Export")
struct LegadoImporterExportTests {

    @Test func exportToLegadoJSON_validFormat() throws {
        let source = BookSource(
            sourceURL: "https://www.example.com",
            sourceName: "Test Export",
            sourceGroup: "Exported",
            sourceType: 0,
            enabled: true,
            searchURL: "https://www.example.com/search?q={{key}}",
            header: "{\"User-Agent\": \"VReader/1.0\"}"
        )
        source.updateSearchRule(BSSearchRule(
            bookList: "div.list",
            name: "h3",
            author: "span.author"
        ))
        source.updateContentRule(BSContentRule(
            content: "div#content",
            replaceRegex: "广告"
        ))
        source.customOrder = 7

        let data = try LegadoImporter.exportSources([source])

        // Parse back as Legado format to verify structure
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(parsed != nil)
        #expect(parsed?.count == 1)

        let dict = parsed![0]
        #expect(dict["bookSourceUrl"] as? String == "https://www.example.com")
        #expect(dict["bookSourceName"] as? String == "Test Export")
        #expect(dict["bookSourceGroup"] as? String == "Exported")
        #expect(dict["bookSourceType"] as? Int == 0)
        #expect(dict["enabled"] as? Bool == true)
        #expect(dict["searchUrl"] as? String == "https://www.example.com/search?q={{key}}")
        #expect(dict["header"] as? String == "{\"User-Agent\": \"VReader/1.0\"}")
        #expect(dict["customOrder"] as? Int == 7)

        // Verify nested rule objects
        let ruleSearch = dict["ruleSearch"] as? [String: Any]
        #expect(ruleSearch != nil)
        #expect(ruleSearch?["bookList"] as? String == "div.list")
        #expect(ruleSearch?["name"] as? String == "h3")

        let ruleContent = dict["ruleContent"] as? [String: Any]
        #expect(ruleContent != nil)
        #expect(ruleContent?["content"] as? String == "div#content")
    }

    @Test func exportImportRoundTrip() throws {
        let original = BookSource(
            sourceURL: "https://roundtrip.example.com",
            sourceName: "Round Trip Source",
            sourceGroup: "Test",
            sourceType: 1,
            enabled: false,
            searchURL: "https://roundtrip.example.com/s?q={{key}}",
            header: "{\"Cookie\": \"abc=123\"}"
        )
        original.updateSearchRule(BSSearchRule(
            bookList: "div.list",
            name: "h3.title",
            author: "span.author",
            bookUrl: "a@href",
            coverUrl: "img@src"
        ))
        original.updateBookInfoRule(BSBookInfoRule(
            name: "h1.name",
            author: "span.author",
            intro: "div.intro",
            coverUrl: "img@src",
            tocUrl: "a.toc@href"
        ))
        original.updateTocRule(BSTocRule(
            chapterList: "ul li",
            chapterName: "a",
            chapterUrl: "a@href",
            nextTocUrl: "a.next@href"
        ))
        original.updateContentRule(BSContentRule(
            content: "div.content",
            nextContentUrl: "a.next@href",
            replaceRegex: "请收藏.*?最新"
        ))
        original.customOrder = 42

        // Export
        let exportedData = try LegadoImporter.exportSources([original])

        // Import back
        let imported = try LegadoImporter.importSources(from: exportedData)

        #expect(imported.count == 1)
        let result = imported[0]

        // Verify identity
        #expect(result.sourceURL == original.sourceURL)
        #expect(result.sourceName == original.sourceName)
        #expect(result.sourceGroup == original.sourceGroup)
        #expect(result.sourceType == original.sourceType)
        #expect(result.enabled == original.enabled)
        #expect(result.searchURL == original.searchURL)
        #expect(result.header == original.header)
        #expect(result.customOrder == original.customOrder)

        // Verify rules
        #expect(result.ruleSearch == original.ruleSearch)
        #expect(result.ruleBookInfo == original.ruleBookInfo)
        #expect(result.ruleToc == original.ruleToc)
        #expect(result.ruleContent == original.ruleContent)
    }

    @Test func exportEmptyArray_validJSON() throws {
        let data = try LegadoImporter.exportSources([])
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(parsed != nil)
        #expect(parsed?.isEmpty == true)
    }
}

// MARK: - Compatibility Classification Tests

@Suite("LegadoImporter — Compatibility Classification")
struct LegadoImporterCompatibilityTests {

    @Test func importSourceWithCSSOnly_classifiedFull() throws {
        let json = """
        {
            "bookSourceUrl": "https://css-only.com",
            "bookSourceName": "CSS Only",
            "bookSourceType": 0,
            "ruleSearch": {
                "bookList": "div.result-list div.item",
                "name": "h3.title",
                "author": "span.author",
                "bookUrl": "a@href"
            },
            "ruleContent": {
                "content": "div#chapter-content",
                "replaceRegex": ":regex:广告.*?移除"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].compatibilityLevel == "Full")
    }

    @Test func importSourceWithXPath_classifiedLimited() throws {
        let json = """
        {
            "bookSourceUrl": "https://xpath-source.com",
            "bookSourceName": "XPath Source",
            "bookSourceType": 0,
            "ruleSearch": {
                "bookList": "//div[@class='result']",
                "name": "//h3/text()",
                "bookUrl": "//a/@href"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].compatibilityLevel == "Limited")
    }

    @Test func importSourceWithJS_classifiedUnsupported() throws {
        let json = """
        {
            "bookSourceUrl": "https://js-source.com",
            "bookSourceName": "JS Source",
            "bookSourceType": 0,
            "ruleSearch": {
                "bookList": "<js>document.querySelectorAll('.item')</js>",
                "name": "{{result.title}}"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].compatibilityLevel == "Unsupported")
    }

    @Test func importSourceWithMixedRules_worstWins() throws {
        // Mix of CSS and XPath rules — classified as Limited (XPath is worst)
        let json = """
        {
            "bookSourceUrl": "https://mixed.com",
            "bookSourceName": "Mixed Source",
            "bookSourceType": 0,
            "ruleSearch": {
                "bookList": "div.list",
                "name": "h3"
            },
            "ruleContent": {
                "content": "//div[@id='content']"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].compatibilityLevel == "Limited")
    }

    @Test func importSourceWithJSAndXPath_unsupportedWins() throws {
        // Mix of XPath and JS — JS is worse, classified as Unsupported
        let json = """
        {
            "bookSourceUrl": "https://js-xpath.com",
            "bookSourceName": "JS+XPath",
            "bookSourceType": 0,
            "ruleSearch": {
                "bookList": "//div[@class='list']",
                "name": "<js>getTitle()</js>"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].compatibilityLevel == "Unsupported")
    }

    @Test func importSourceWithNoRules_classifiedFull() throws {
        let json = """
        {
            "bookSourceUrl": "https://no-rules.com",
            "bookSourceName": "No Rules"
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].compatibilityLevel == "Full")
    }

    @Test func importSourceWithDoubleBraces_classifiedUnsupported() throws {
        let json = """
        {
            "bookSourceUrl": "https://braces.com",
            "bookSourceName": "Braces Source",
            "bookSourceType": 0,
            "ruleSearch": {
                "bookList": "div.list",
                "name": "{{result.name}}"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].compatibilityLevel == "Unsupported")
    }
}

// MARK: - Performance Tests

@Suite("LegadoImporter — Performance")
struct LegadoImporterPerformanceTests {

    @Test func import500Sources_performsUnder2Seconds() throws {
        // Generate 500 sources
        var sourceDicts: [[String: Any]] = []
        for i in 0..<500 {
            sourceDicts.append([
                "bookSourceUrl": "https://source-\(i).example.com",
                "bookSourceName": "Source \(i)",
                "bookSourceType": 0,
                "enabled": true,
                "searchUrl": "https://source-\(i).example.com/s?q={{key}}",
                "ruleSearch": [
                    "bookList": "div.list-\(i)",
                    "name": "h3.title",
                    "author": "span.author",
                    "bookUrl": "a@href",
                    "coverUrl": "img@src"
                ],
                "ruleContent": [
                    "content": "div#content-\(i)",
                    "replaceRegex": "ad-pattern-\(i)"
                ]
            ] as [String: Any])
        }
        let data = try JSONSerialization.data(
            withJSONObject: sourceDicts,
            options: []
        )

        let start = CFAbsoluteTimeGetCurrent()
        let sources = try LegadoImporter.importSources(from: data)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(sources.count == 500)
        #expect(elapsed < 2.0, "Import of 500 sources took \(elapsed)s, should be <2s")
    }
}

// MARK: - Edge Case Tests

@Suite("LegadoImporter — Edge Cases")
struct LegadoImporterEdgeCaseTests {

    @Test func importEmptyBookSourceUrl_skips() throws {
        let json = """
        [
            {
                "bookSourceUrl": "",
                "bookSourceName": "Empty URL"
            },
            {
                "bookSourceUrl": "https://valid.com",
                "bookSourceName": "Valid"
            }
        ]
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].sourceURL == "https://valid.com")
    }

    @Test func importWhitespaceOnlyUrl_skips() throws {
        let json = """
        {
            "bookSourceUrl": "   ",
            "bookSourceName": "Whitespace URL"
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.isEmpty)
    }

    @Test func importCJKSourceName_preserved() throws {
        let json = """
        {
            "bookSourceUrl": "https://cn.example.com",
            "bookSourceName": "笔趣阁小说网",
            "bookSourceGroup": "中文小说"
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].sourceName == "笔趣阁小说网")
        #expect(sources[0].sourceGroup == "中文小说")
    }

    @Test func importMissingBookSourceUrl_skips() throws {
        let json = """
        {
            "bookSourceName": "No URL"
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.isEmpty)
    }

    @Test func importMissingBookSourceName_usesUrlAsFallback() throws {
        let json = """
        {
            "bookSourceUrl": "https://no-name.com"
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].sourceName == "https://no-name.com")
    }

    @Test func importSingleObjectNotArray_parsesSingle() throws {
        // Legado can export a single source as an object (not wrapped in array)
        let json = """
        {
            "bookSourceUrl": "https://single.com",
            "bookSourceName": "Single Object"
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        #expect(sources[0].sourceURL == "https://single.com")
    }

    @Test func importLastUpdateTime_converted() throws {
        let json = """
        {
            "bookSourceUrl": "https://time.com",
            "bookSourceName": "Time Test",
            "lastUpdateTime": 1700000000000
        }
        """
        let data = json.data(using: .utf8)!
        let sources = try LegadoImporter.importSources(from: data)

        #expect(sources.count == 1)
        // Legado uses milliseconds since epoch; VReader uses Date
        #expect(sources[0].lastUpdateTime != nil)
        let expectedDate = Date(timeIntervalSince1970: 1700000000)
        let diff = abs(sources[0].lastUpdateTime!.timeIntervalSince(expectedDate))
        #expect(diff < 1.0)
    }
}
