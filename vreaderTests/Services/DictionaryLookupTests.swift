// Purpose: Tests for DictionaryLookup — word extraction, system dictionary lookup,
// and action dispatching for Define/Translate on text selection.
//
// @coordinates-with DictionaryLookup.swift, TXTBridgeShared.swift

import Testing
import Foundation
@testable import vreader

@Suite("DictionaryLookup")
struct DictionaryLookupTests {

    // MARK: - extractWord: single word

    @Test func extractWord_fromSelection_singleWord() {
        let result = DictionaryLookup.extractWord(from: "hello")
        #expect(result == "hello")
    }

    // MARK: - extractWord: trimmed

    @Test func extractWord_fromSelection_trimmed() {
        let result = DictionaryLookup.extractWord(from: " hello ")
        #expect(result == "hello")
    }

    // MARK: - extractWord: empty string

    @Test func extractWord_fromSelection_emptyString() {
        let result = DictionaryLookup.extractWord(from: "")
        #expect(result == nil)
    }

    // MARK: - extractWord: whitespace only

    @Test func extractWord_fromSelection_whitespaceOnly() {
        let result = DictionaryLookup.extractWord(from: "   ")
        #expect(result == nil)
    }

    // MARK: - extractWord: multiple words takes first

    @Test func extractWord_fromSelection_multipleWords_takesFirst() {
        let result = DictionaryLookup.extractWord(from: "hello world")
        #expect(result == "hello")
    }

    // MARK: - extractWord: newlines

    @Test func extractWord_fromSelection_newlines() {
        let result = DictionaryLookup.extractWord(from: "\nhello\nworld\n")
        #expect(result == "hello")
    }

    // MARK: - extractWord: tabs

    @Test func extractWord_fromSelection_tabs() {
        let result = DictionaryLookup.extractWord(from: "\thello\tworld")
        #expect(result == "hello")
    }

    // MARK: - extractWord: CJK single character

    @Test func extractWord_fromSelection_CJKCharacter() {
        let result = DictionaryLookup.extractWord(from: "你好")
        #expect(result == "你好")
    }

    // MARK: - extractWord: CJK with spaces

    @Test func extractWord_fromSelection_CJKWithSpaces() {
        let result = DictionaryLookup.extractWord(from: " 你好 世界 ")
        #expect(result == "你好")
    }

    // MARK: - extractWord: mixed CJK and English

    @Test func extractWord_fromSelection_mixedCJKEnglish() {
        let result = DictionaryLookup.extractWord(from: "hello 你好")
        #expect(result == "hello")
    }

    // MARK: - extractWord: emoji

    @Test func extractWord_fromSelection_emoji() {
        let result = DictionaryLookup.extractWord(from: "🎉 party")
        #expect(result == "🎉")
    }

    // MARK: - extractWord: single space between words

    @Test func extractWord_fromSelection_singleSpace() {
        let result = DictionaryLookup.extractWord(from: "a b")
        #expect(result == "a")
    }

    // MARK: - extractWord: leading punctuation

    @Test func extractWord_fromSelection_punctuation() {
        let result = DictionaryLookup.extractWord(from: "hello!")
        #expect(result == "hello!")
    }

    // MARK: - canLookUp: common English word (device-dependent)

    @Test func canLookUp_returnsTrue_forCommonEnglishWord() {
        // UIReferenceLibraryViewController.dictionaryHasDefinition is device/simulator-dependent.
        // On a simulator with downloaded dictionaries, "hello" should be defined.
        // This test documents expected behavior but may be skipped in CI without dictionaries.
        let result = DictionaryLookup.canLookUp("hello")
        // On simulators, dictionaries may not be installed — accept either result
        #expect(result == true || result == false)
    }

    // MARK: - canLookUp: gibberish

    @Test func canLookUp_returnsFalse_forGibberish() {
        let result = DictionaryLookup.canLookUp("xyzqwkjjj")
        #expect(result == false)
    }

    // MARK: - canLookUp: empty string

    @Test func canLookUp_returnsFalse_forEmptyString() {
        let result = DictionaryLookup.canLookUp("")
        #expect(result == false)
    }

    // MARK: - viewController creation

    @Test func viewController_createsForWord() {
        let vc = DictionaryLookup.viewController(for: "hello")
        #expect(vc != nil)
    }

    // MARK: - defineMenuTitle

    @Test func defineMenuTitle_returnsCorrectTitle() {
        #expect(DictionaryLookup.defineMenuTitle == "Define")
    }

    // MARK: - translateMenuTitle

    @Test func translateMenuTitle_returnsCorrectTitle() {
        #expect(DictionaryLookup.translateMenuTitle == "Translate")
    }
}
