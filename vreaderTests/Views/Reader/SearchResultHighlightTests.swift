import Testing
import Foundation
@testable import vreader

@Suite("HighlightedSnippet")
struct SearchResultHighlightTests {

    @Test func boldsQueryTerm() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "world")
        let plain = String(result.characters)
        #expect(plain == "hello world")
        var boldCount = 0
        for run in result.runs { if run.font != nil { boldCount += 1 } }
        #expect(boldCount == 1, "Matched text should have a font attribute set")
    }

    @Test func caseInsensitiveMatch() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "WORLD")
        let plain = String(result.characters)
        #expect(plain == "hello world")
        var boldCount = 0
        for run in result.runs { if run.font != nil { boldCount += 1 } }
        #expect(boldCount == 1, "Case-insensitive match should be highlighted")
    }

    @Test func multipleMatches() {
        let result = HighlightedSnippet.highlight(snippet: "the cat sat on the mat", query: "the")
        let plain = String(result.characters)
        #expect(plain == "the cat sat on the mat")
        var boldCount = 0
        for run in result.runs { if run.font != nil { boldCount += 1 } }
        #expect(boldCount == 2, "Both occurrences of the should be highlighted")
    }

    @Test func noMatchReturnsPlainText() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "xyz")
        let plain = String(result.characters)
        #expect(plain == "hello world")
        for run in result.runs { #expect(run.font == nil) }
    }

    @Test func emptyQueryReturnsPlainText() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "")
        let plain = String(result.characters)
        #expect(plain == "hello world")
        for run in result.runs { #expect(run.font == nil) }
    }

    @Test func whitespaceOnlyQueryReturnsPlainText() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "   ")
        let plain = String(result.characters)
        #expect(plain == "hello world")
        for run in result.runs { #expect(run.font == nil) }
    }

    @Test func cjkQueryHighlighted() {
        let result = HighlightedSnippet.highlight(snippet: "今天天气很好", query: "天气")
        let plain = String(result.characters)
        #expect(plain == "今天天气很好")
        var boldCount = 0
        for run in result.runs { if run.font != nil { boldCount += 1 } }
        #expect(boldCount == 1, "CJK query should be highlighted")
    }

    @Test func specialRegexCharsTreatedAsLiteral() {
        let result = HighlightedSnippet.highlight(snippet: "price is $9.99 today", query: "$9.99")
        let plain = String(result.characters)
        #expect(plain == "price is $9.99 today")
        var boldCount = 0
        for run in result.runs { if run.font != nil { boldCount += 1 } }
        #expect(boldCount == 1, "Regex special chars should match literally")
    }

    @Test func queryWithAsteriskTreatedAsLiteral() {
        let result = HighlightedSnippet.highlight(snippet: "use a* for wildcard", query: "a*")
        let plain = String(result.characters)
        #expect(plain == "use a* for wildcard")
        var boldCount = 0
        for run in result.runs { if run.font != nil { boldCount += 1 } }
        #expect(boldCount == 1, "Asterisk should match literally")
    }

    @Test func queryAtStartOfSnippet() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "hello")
        let firstRun = result.runs.first!
        #expect(firstRun.font != nil, "Match at start should be highlighted")
    }

    @Test func queryAtEndOfSnippet() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "world")
        var lastBold: AttributedString.Runs.Run?
        for run in result.runs { if run.font != nil { lastBold = run } }
        #expect(lastBold != nil, "Match at end should be highlighted")
    }

    @Test func emptySnippetReturnsEmptyAttributedString() {
        let result = HighlightedSnippet.highlight(snippet: "", query: "hello")
        #expect(result.characters.count == 0)
    }

    @Test func queryMatchesEntireSnippet() {
        let result = HighlightedSnippet.highlight(snippet: "hello", query: "hello")
        let firstRun = result.runs.first!
        #expect(firstRun.font != nil, "Full match should be highlighted")
    }

    @Test func stripsFTS5BoldTags() {
        let result = HighlightedSnippet.highlight(snippet: "hello <b>world</b> here", query: "world")
        let plain = String(result.characters)
        #expect(plain == "hello world here", "FTS5 tags should be stripped")
        var boldCount = 0
        for run in result.runs { if run.font != nil { boldCount += 1 } }
        #expect(boldCount == 1)
    }
}
