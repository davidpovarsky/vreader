// Purpose: Tests for LegadoRuleParser — parsing Legado rule syntax into
// structured components (selector, attribute, index, rule type detection).
//
// @coordinates-with: LegadoRuleParser.swift

import Testing
import Foundation
@testable import vreader

@Suite("LegadoRuleParser")
struct LegadoRuleParserTests {

    // MARK: - Rule Type Detection

    @Test func detectsCSS_plainSelector() {
        let parsed = LegadoRuleParser.parse("div.content")
        #expect(parsed.type == .css)
    }

    @Test func detectsCSS_withAttribute() {
        let parsed = LegadoRuleParser.parse("a@href")
        #expect(parsed.type == .css)
    }

    @Test func detectsRegex_withPrefix() {
        let parsed = LegadoRuleParser.parse(#":regex:<title>([^<]+)</title>"#)
        #expect(parsed.type == .regex)
    }

    @Test func detectsXPath_doubleSlash() {
        let parsed = LegadoRuleParser.parse("//div[@class='result']")
        #expect(parsed.type == .xpath)
    }

    @Test func detectsXPath_singleSlash() {
        let parsed = LegadoRuleParser.parse("/html/body/div")
        #expect(parsed.type == .xpath)
    }

    // MARK: - CSS Parsing

    @Test func parsesSelector_simple() {
        let parsed = LegadoRuleParser.parse("p")
        #expect(parsed.selector == "p")
        #expect(parsed.attribute == nil)
        #expect(parsed.index == nil)
    }

    @Test func parsesSelector_withClass() {
        let parsed = LegadoRuleParser.parse(".bookname")
        #expect(parsed.selector == ".bookname")
        #expect(parsed.attribute == nil)
        #expect(parsed.index == nil)
    }

    @Test func parsesSelector_withAttribute() {
        let parsed = LegadoRuleParser.parse("a@href")
        #expect(parsed.selector == "a")
        #expect(parsed.attribute == "href")
        #expect(parsed.index == nil)
    }

    @Test func parsesSelector_withIndex() {
        let parsed = LegadoRuleParser.parse("li!0")
        #expect(parsed.selector == "li")
        #expect(parsed.attribute == nil)
        #expect(parsed.index == 0)
    }

    @Test func parsesSelector_withAttributeAndIndex() {
        let parsed = LegadoRuleParser.parse("a@href!1")
        #expect(parsed.selector == "a")
        #expect(parsed.attribute == "href")
        #expect(parsed.index == 1)
    }

    @Test func parsesSelector_negativeIndex() {
        let parsed = LegadoRuleParser.parse("li!-1")
        #expect(parsed.selector == "li")
        #expect(parsed.index == -1)
    }

    @Test func parsesSelector_classWithTagAndAttr() {
        let parsed = LegadoRuleParser.parse("a.link@href")
        #expect(parsed.selector == "a.link")
        #expect(parsed.attribute == "href")
    }

    @Test func parsesSelector_nestedWithAttribute() {
        let parsed = LegadoRuleParser.parse("div.container a@href")
        #expect(parsed.selector == "div.container a")
        #expect(parsed.attribute == "href")
    }

    // MARK: - Regex Parsing

    @Test func parsesRegex_extractsPattern() {
        let parsed = LegadoRuleParser.parse(#":regex:title="([^"]+)""#)
        #expect(parsed.type == .regex)
        #expect(parsed.regexPattern == #"title="([^"]+)""#)
    }

    @Test func parsesRegex_emptyPattern() {
        let parsed = LegadoRuleParser.parse(":regex:")
        #expect(parsed.type == .regex)
        #expect(parsed.regexPattern == "")
    }

    // MARK: - Edge Cases

    @Test func parse_emptyString() {
        let parsed = LegadoRuleParser.parse("")
        #expect(parsed.type == .css)
        #expect(parsed.selector == "")
    }

    @Test func parse_whitespaceOnly() {
        let parsed = LegadoRuleParser.parse("   ")
        #expect(parsed.type == .css)
        #expect(parsed.selector == "")
    }

    @Test func parsesSelector_idSelector() {
        let parsed = LegadoRuleParser.parse("#main-content")
        #expect(parsed.type == .css)
        #expect(parsed.selector == "#main-content")
    }

    @Test func parsesSelector_multipleClasses() {
        let parsed = LegadoRuleParser.parse("div.a.b")
        #expect(parsed.type == .css)
        #expect(parsed.selector == "div.a.b")
    }
}
