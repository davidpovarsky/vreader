// Purpose: Tests for CSSRuleEvaluator — minimal HTML tag extraction
// using Foundation regex (no SwiftSoup dependency).
//
// @coordinates-with: CSSRuleEvaluator.swift

import Testing
import Foundation
@testable import vreader

@Suite("CSSRuleEvaluator")
struct CSSRuleEvaluatorTests {

    // MARK: - Tag Selector

    @Test func tagSelector_findsParagraphs() {
        let html = "<p>First</p><p>Second</p>"
        let results = CSSRuleEvaluator.evaluate(
            selector: "p", attribute: nil, index: nil, html: html, baseURL: nil
        )
        #expect(results == ["First", "Second"])
    }

    @Test func tagSelector_findsAnchors() {
        let html = "<a href='/x'>Link</a>"
        let results = CSSRuleEvaluator.evaluate(
            selector: "a", attribute: nil, index: nil, html: html, baseURL: nil
        )
        #expect(results == ["Link"])
    }

    // MARK: - Class Selector

    @Test func classSelector_dot() {
        let html = """
        <div class="item active">Matched</div>
        <div class="other">Not Matched</div>
        """
        let results = CSSRuleEvaluator.evaluate(
            selector: ".item", attribute: nil, index: nil, html: html, baseURL: nil
        )
        #expect(results == ["Matched"])
    }

    @Test func classSelector_tagDotClass() {
        let html = """
        <span class="name">Alice</span>
        <div class="name">Bob</div>
        """
        let results = CSSRuleEvaluator.evaluate(
            selector: "span.name", attribute: nil, index: nil, html: html, baseURL: nil
        )
        #expect(results == ["Alice"])
    }

    // MARK: - ID Selector

    @Test func idSelector_hash() {
        let html = """
        <div id="content">Content Here</div>
        <div id="sidebar">Sidebar</div>
        """
        let results = CSSRuleEvaluator.evaluate(
            selector: "#content", attribute: nil, index: nil, html: html, baseURL: nil
        )
        #expect(results == ["Content Here"])
    }

    // MARK: - Attribute Extraction

    @Test func attribute_href() {
        let html = """
        <a href="/page/1">Link One</a>
        <a href="/page/2">Link Two</a>
        """
        let results = CSSRuleEvaluator.evaluate(
            selector: "a", attribute: "href", index: nil, html: html, baseURL: nil
        )
        #expect(results == ["/page/1", "/page/2"])
    }

    @Test func attribute_src() {
        let html = """
        <img src="image.jpg" alt="Photo">
        """
        let results = CSSRuleEvaluator.evaluate(
            selector: "img", attribute: "src", index: nil, html: html, baseURL: nil
        )
        #expect(results == ["image.jpg"])
    }

    @Test func attribute_title() {
        let html = """
        <a href="/x" title="Tooltip Text">Link</a>
        """
        let results = CSSRuleEvaluator.evaluate(
            selector: "a", attribute: "title", index: nil, html: html, baseURL: nil
        )
        #expect(results == ["Tooltip Text"])
    }

    // MARK: - Index Selection

    @Test func index_firstElement() {
        let html = "<li>A</li><li>B</li><li>C</li>"
        let results = CSSRuleEvaluator.evaluate(
            selector: "li", attribute: nil, index: 0, html: html, baseURL: nil
        )
        #expect(results == ["A"])
    }

    @Test func index_lastElement() {
        let html = "<li>A</li><li>B</li><li>C</li>"
        let results = CSSRuleEvaluator.evaluate(
            selector: "li", attribute: nil, index: 2, html: html, baseURL: nil
        )
        #expect(results == ["C"])
    }

    @Test func index_negative() {
        let html = "<li>A</li><li>B</li><li>C</li>"
        let results = CSSRuleEvaluator.evaluate(
            selector: "li", attribute: nil, index: -1, html: html, baseURL: nil
        )
        #expect(results == ["C"])
    }

    @Test func index_outOfBounds() {
        let html = "<li>A</li>"
        let results = CSSRuleEvaluator.evaluate(
            selector: "li", attribute: nil, index: 5, html: html, baseURL: nil
        )
        #expect(results.isEmpty)
    }

    // MARK: - URL Resolution

    @Test func urlResolution_relativeHref() {
        let html = "<a href=\"/chapter/1\">Ch 1</a>"
        let base = URL(string: "https://example.com")!
        let results = CSSRuleEvaluator.evaluate(
            selector: "a", attribute: "href", index: nil, html: html, baseURL: base
        )
        #expect(results == ["https://example.com/chapter/1"])
    }

    @Test func urlResolution_absoluteHref_unchanged() {
        let html = "<a href=\"https://other.com/page\">Link</a>"
        let base = URL(string: "https://example.com")!
        let results = CSSRuleEvaluator.evaluate(
            selector: "a", attribute: "href", index: nil, html: html, baseURL: base
        )
        #expect(results == ["https://other.com/page"])
    }

    @Test func urlResolution_noBase_returnRaw() {
        let html = "<a href=\"/relative\">Link</a>"
        let results = CSSRuleEvaluator.evaluate(
            selector: "a", attribute: "href", index: nil, html: html, baseURL: nil
        )
        #expect(results == ["/relative"])
    }

    // MARK: - Empty / No Matches

    @Test func noMatches_returnsEmpty() {
        let html = "<div>Content</div>"
        let results = CSSRuleEvaluator.evaluate(
            selector: "span", attribute: nil, index: nil, html: html, baseURL: nil
        )
        #expect(results.isEmpty)
    }

    @Test func emptyHTML_returnsEmpty() {
        let results = CSSRuleEvaluator.evaluate(
            selector: "p", attribute: nil, index: nil, html: "", baseURL: nil
        )
        #expect(results.isEmpty)
    }

    @Test func emptySelector_returnsEmpty() {
        let html = "<p>Text</p>"
        let results = CSSRuleEvaluator.evaluate(
            selector: "", attribute: nil, index: nil, html: html, baseURL: nil
        )
        #expect(results.isEmpty)
    }

    // MARK: - Nested Content (Strip Inner Tags)

    @Test func nestedContent_stripsInnerTags() {
        let html = "<p>Hello <strong>World</strong></p>"
        let results = CSSRuleEvaluator.evaluate(
            selector: "p", attribute: nil, index: nil, html: html, baseURL: nil
        )
        #expect(results == ["Hello World"])
    }

    // MARK: - CJK Content

    @Test func cjkContent_extracted() {
        let html = "<p>第一章 开始冒险</p>"
        let results = CSSRuleEvaluator.evaluate(
            selector: "p", attribute: nil, index: nil, html: html, baseURL: nil
        )
        #expect(results == ["第一章 开始冒险"])
    }

    // MARK: - Self-closing Tags

    @Test func selfClosingTag_attribute() {
        let html = "<img src=\"cover.png\" />"
        let results = CSSRuleEvaluator.evaluate(
            selector: "img", attribute: "src", index: nil, html: html, baseURL: nil
        )
        #expect(results == ["cover.png"])
    }

    // MARK: - Descendant Selector

    @Test func descendantSelector_tagTag() {
        let html = """
        <div class="outer">
          <p>Inside</p>
        </div>
        <p>Outside</p>
        """
        let results = CSSRuleEvaluator.evaluate(
            selector: "div.outer p", attribute: nil, index: nil, html: html, baseURL: nil
        )
        #expect(results == ["Inside"])
    }
}
