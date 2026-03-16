// Purpose: Tests for HighlightedSnippet — verifying query highlighting
// in search result snippets, including multi-word tokenized queries.
//
// @coordinates-with: HighlightedSnippet.swift

import Testing
import SwiftUI
@testable import vreader

@Suite("HighlightedSnippet")
struct HighlightedSnippetTests {

    // MARK: - Basic

    @Test func emptyQuery_returnsPlainText() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "")
        #expect(String(result.characters) == "hello world")
    }

    @Test func emptySnippet_returnsEmpty() {
        let result = HighlightedSnippet.highlight(snippet: "", query: "foo")
        #expect(String(result.characters) == "")
    }

    @Test func singleWordMatch_highlighted() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "hello")
        #expect(String(result.characters) == "hello world")
        // "hello" should be bolded — we verify by checking the range has bold font
        let helloRange = result.characters.startIndex..<result.characters.index(result.characters.startIndex, offsetBy: 5)
        let helloSlice = result[helloRange]
        #expect(helloSlice.font != nil) // bold applied
    }

    @Test func caseInsensitiveMatch() {
        let result = HighlightedSnippet.highlight(snippet: "Hello World", query: "hello")
        #expect(String(result.characters) == "Hello World")
    }

    @Test func fts5TagsStripped() {
        let result = HighlightedSnippet.highlight(snippet: "<b>hello</b> world", query: "hello")
        #expect(String(result.characters) == "hello world")
    }

    @Test func noMatch_returnsPlainText() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "xyz")
        #expect(String(result.characters) == "hello world")
    }

    // MARK: - Multi-word queries (Issue 4)

    @Test func multiWordQuery_highlightsBothWords() {
        // "foo bar" should highlight "foo" and "bar" independently
        let result = HighlightedSnippet.highlight(
            snippet: "foo is here and bar is there",
            query: "foo bar"
        )
        let text = String(result.characters)
        #expect(text == "foo is here and bar is there")
        // Both "foo" and "bar" should be found and bolded.
        // The result should contain at least 2 bold runs.
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        #expect(boldRunCount >= 2, "Expected at least 2 bold runs for 'foo' and 'bar'")
    }

    @Test func multiWordQuery_worksWhenExactPhraseNotPresent() {
        // The snippet contains "foo" and "bar" but NOT the exact phrase "foo bar"
        let result = HighlightedSnippet.highlight(
            snippet: "bar appears first, then foo appears",
            query: "foo bar"
        )
        let text = String(result.characters)
        #expect(text == "bar appears first, then foo appears")
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        #expect(boldRunCount >= 2, "Expected at least 2 bold runs")
    }

    @Test func multiWordQuery_duplicateWordHighlightsAllOccurrences() {
        let result = HighlightedSnippet.highlight(
            snippet: "foo foo foo bar",
            query: "foo bar"
        )
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        // 3 "foo" + 1 "bar" = 4 bold runs
        #expect(boldRunCount >= 4)
    }

    @Test func singleWordQuery_stillWorks() {
        // Ensure the multi-word change doesn't break single-word queries
        let result = HighlightedSnippet.highlight(
            snippet: "hello beautiful world",
            query: "beautiful"
        )
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        #expect(boldRunCount == 1)
    }

    @Test func whitespaceOnlyQuery_returnsPlainText() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "   ")
        #expect(String(result.characters) == "hello world")
    }

    @Test func multiWordQuery_withExtraSpaces_handledGracefully() {
        let result = HighlightedSnippet.highlight(
            snippet: "foo and bar here",
            query: "  foo   bar  "
        )
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        #expect(boldRunCount >= 2)
    }

    @Test func multiWordQuery_overlappingMatches_handled() {
        // Edge: word tokens that partially overlap in the snippet
        let result = HighlightedSnippet.highlight(
            snippet: "abcabc",
            query: "abc"
        )
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        #expect(boldRunCount >= 2)
    }

    @Test func regexSpecialCharsInQuery_escaped() {
        // Ensure regex special chars don't break anything
        let result = HighlightedSnippet.highlight(
            snippet: "price is $100 (total)",
            query: "$100 (total)"
        )
        let text = String(result.characters)
        #expect(text == "price is $100 (total)")
    }
}
