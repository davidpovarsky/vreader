// Purpose: Tests for the BookSource rule engine — CSS selector extraction,
// regex extraction, Legado syntax operators (@, !), and auto-detection.
//
// @coordinates-with: RuleEngine.swift, CSSRuleEvaluator.swift,
//   RegexRuleEvaluator.swift, LegadoRuleParser.swift

import Testing
import Foundation
@testable import vreader

@Suite("RuleEngine")
struct RuleEngineTests {

    // MARK: - CSS Rule: Extract Text by Class

    @Test func cssRule_extractText_byClass() {
        let html = """
        <html><body>
          <div class="bookname">The Great Novel</div>
          <div class="author">Jane Doe</div>
        </body></html>
        """
        let results = RuleEngine.evaluate(rule: ".bookname", html: html, baseURL: nil)
        #expect(results == ["The Great Novel"])
    }

    // MARK: - CSS Rule: Extract Attribute (href)

    @Test func cssRule_extractAttribute_href() {
        let html = """
        <html><body>
          <a href="/chapter/1" class="link">Chapter 1</a>
          <a href="/chapter/2" class="link">Chapter 2</a>
        </body></html>
        """
        let results = RuleEngine.evaluate(rule: "a.link@href", html: html, baseURL: nil)
        #expect(results == ["/chapter/1", "/chapter/2"])
    }

    // MARK: - CSS Rule: Extract List (Multiple Matches)

    @Test func cssRule_extractList_multipleMatches() {
        let html = """
        <html><body>
          <ul>
            <li>Item One</li>
            <li>Item Two</li>
            <li>Item Three</li>
          </ul>
        </body></html>
        """
        let results = RuleEngine.evaluate(rule: "li", html: html, baseURL: nil)
        #expect(results == ["Item One", "Item Two", "Item Three"])
    }

    // MARK: - Regex Rule: Extract Group

    @Test func regexRule_extractGroup() {
        let html = """
        <html><head><title>My Book Title</title></head><body></body></html>
        """
        let results = RuleEngine.evaluate(
            rule: #":regex:<title>([^<]+)</title>"#,
            html: html,
            baseURL: nil
        )
        #expect(results == ["My Book Title"])
    }

    // MARK: - Regex Rule: Replace Pattern

    @Test func regexRule_replacePattern() {
        let input = "Chapter 001: The Beginning"
        let result = RegexRuleEvaluator.replace(
            pattern: #"Chapter \d+: "#,
            replacement: "",
            in: input
        )
        #expect(result == "The Beginning")
    }

    // MARK: - RuleEngine: Dispatches Correctly

    @Test func ruleEngine_dispatchesCorrectly() {
        let html = "<html><body><p>Hello</p></body></html>"

        // CSS rule (no prefix)
        let cssResults = RuleEngine.evaluate(rule: "p", html: html, baseURL: nil)
        #expect(cssResults == ["Hello"])

        // Regex rule (with :regex: prefix)
        let regexResults = RuleEngine.evaluate(
            rule: #":regex:<p>([^<]+)</p>"#,
            html: html,
            baseURL: nil
        )
        #expect(regexResults == ["Hello"])
    }

    // MARK: - RuleEngine: Empty Rule Returns Empty

    @Test func ruleEngine_emptyRule_returnsEmpty() {
        let html = "<html><body><p>Text</p></body></html>"
        let results = RuleEngine.evaluate(rule: "", html: html, baseURL: nil)
        #expect(results.isEmpty)
    }

    // MARK: - RuleEngine: Invalid HTML Returns Empty

    @Test func ruleEngine_invalidHTML_returnsEmpty() {
        // Completely non-HTML content
        let results = RuleEngine.evaluate(rule: "p", html: "", baseURL: nil)
        #expect(results.isEmpty)
    }

    // MARK: - Legado Syntax: @ Operator (Attribute Access)

    @Test func legadoSyntax_atOperator_accessesAttribute() {
        let html = """
        <html><body>
          <a href="https://example.com/book/1">Book One</a>
          <a href="https://example.com/book/2">Book Two</a>
        </body></html>
        """
        let results = RuleEngine.evaluate(rule: "a@href", html: html, baseURL: nil)
        #expect(results == ["https://example.com/book/1", "https://example.com/book/2"])
    }

    // MARK: - Legado Syntax: ! Operator (Index Selection)

    @Test func legadoSyntax_bangOperator_selectsByIndex() {
        let html = """
        <html><body>
          <ul>
            <li>First</li>
            <li>Second</li>
            <li>Third</li>
          </ul>
        </body></html>
        """
        let results = RuleEngine.evaluate(rule: "li!0", html: html, baseURL: nil)
        #expect(results == ["First"])
    }

    @Test func legadoSyntax_bangOperator_lastIndex() {
        let html = """
        <html><body>
          <ul>
            <li>First</li>
            <li>Second</li>
            <li>Third</li>
          </ul>
        </body></html>
        """
        let results = RuleEngine.evaluate(rule: "li!2", html: html, baseURL: nil)
        #expect(results == ["Third"])
    }

    @Test func legadoSyntax_bangOperator_negativeIndex() {
        let html = """
        <html><body>
          <ul>
            <li>First</li>
            <li>Second</li>
            <li>Third</li>
          </ul>
        </body></html>
        """
        // !-1 means last element (Legado convention)
        let results = RuleEngine.evaluate(rule: "li!-1", html: html, baseURL: nil)
        #expect(results == ["Third"])
    }

    // MARK: - Legado Syntax: Relative URL Resolution

    @Test func legadoSyntax_relativeURL_resolved() {
        let html = """
        <html><body>
          <a href="/chapter/1">Chapter 1</a>
        </body></html>
        """
        let base = URL(string: "https://example.com")!
        let results = RuleEngine.evaluate(rule: "a@href", html: html, baseURL: base)
        #expect(results == ["https://example.com/chapter/1"])
    }

    @Test func legadoSyntax_absoluteURL_notModified() {
        let html = """
        <html><body>
          <a href="https://other.com/page">Link</a>
        </body></html>
        """
        let base = URL(string: "https://example.com")!
        let results = RuleEngine.evaluate(rule: "a@href", html: html, baseURL: base)
        #expect(results == ["https://other.com/page"])
    }

    // MARK: - CJK Content Extraction

    @Test func cjkContent_correctExtraction() {
        let html = """
        <html><body>
          <div class="content">
            <p>第一章 武林大会</p>
            <p>少年の冒険が始まった</p>
            <p>한국어 소설 내용</p>
          </div>
        </body></html>
        """
        let results = RuleEngine.evaluate(rule: "div.content p", html: html, baseURL: nil)
        #expect(results.count == 3)
        #expect(results[0] == "第一章 武林大会")
        #expect(results[1] == "少年の冒険が始まった")
        #expect(results[2] == "한국어 소설 내용")
    }

    // MARK: - evaluateSingle

    @Test func evaluateSingle_returnsFirstMatch() {
        let html = """
        <html><body>
          <h1 class="title">Book Title</h1>
          <p>Some text</p>
        </body></html>
        """
        let result = RuleEngine.evaluateSingle(rule: ".title", html: html, baseURL: nil)
        #expect(result == "Book Title")
    }

    @Test func evaluateSingle_emptyRule_returnsNil() {
        let result = RuleEngine.evaluateSingle(rule: "", html: "<p>Text</p>", baseURL: nil)
        #expect(result == nil)
    }

    // MARK: - Combined @ and ! Operators

    @Test func legadoSyntax_combinedAtBang() {
        let html = """
        <html><body>
          <a href="/first">First</a>
          <a href="/second">Second</a>
          <a href="/third">Third</a>
        </body></html>
        """
        let results = RuleEngine.evaluate(rule: "a@href!1", html: html, baseURL: nil)
        #expect(results == ["/second"])
    }

    // MARK: - Nested Selector

    @Test func cssRule_nestedSelector() {
        let html = """
        <html><body>
          <div class="container">
            <span class="name">Inside</span>
          </div>
          <span class="name">Outside</span>
        </body></html>
        """
        let results = RuleEngine.evaluate(rule: "div.container span.name", html: html, baseURL: nil)
        #expect(results == ["Inside"])
    }

    // MARK: - Tag with ID

    @Test func cssRule_idSelector() {
        let html = """
        <html><body>
          <div id="main-content">Main Content Here</div>
        </body></html>
        """
        let results = RuleEngine.evaluate(rule: "#main-content", html: html, baseURL: nil)
        #expect(results == ["Main Content Here"])
    }

    // MARK: - Whitespace-only Rule

    @Test func ruleEngine_whitespaceOnlyRule_returnsEmpty() {
        let html = "<html><body><p>Text</p></body></html>"
        let results = RuleEngine.evaluate(rule: "   ", html: html, baseURL: nil)
        #expect(results.isEmpty)
    }

    // MARK: - Regex: No Match Returns Empty

    @Test func regexRule_noMatch_returnsEmpty() {
        let html = "<html><body>No match here</body></html>"
        let results = RuleEngine.evaluate(
            rule: #":regex:ZZZZZ(\d+)"#,
            html: html,
            baseURL: nil
        )
        #expect(results.isEmpty)
    }

    // MARK: - Regex: Full Match (No Capture Group)

    @Test func regexRule_fullMatch_noCaptureGroup() {
        let html = "Price: $42.99 today"
        let results = RuleEngine.evaluate(
            rule: #":regex:\$\d+\.\d+"#,
            html: html,
            baseURL: nil
        )
        #expect(results == ["$42.99"])
    }

    // MARK: - CSS: Attribute src

    @Test func cssRule_extractAttribute_src() {
        let html = """
        <html><body>
          <img src="cover.jpg" alt="Cover">
        </body></html>
        """
        let results = RuleEngine.evaluate(rule: "img@src", html: html, baseURL: nil)
        #expect(results == ["cover.jpg"])
    }

    // MARK: - Bang Operator: Out of Bounds

    @Test func legadoSyntax_bangOperator_outOfBounds_returnsEmpty() {
        let html = """
        <html><body>
          <li>Only Item</li>
        </body></html>
        """
        let results = RuleEngine.evaluate(rule: "li!5", html: html, baseURL: nil)
        #expect(results.isEmpty)
    }
}
