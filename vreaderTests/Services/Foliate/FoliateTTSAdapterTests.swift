// Purpose: Tests for FoliateTTSAdapter — JS string generation and TTS block parsing.
// Covers: JS generation for TTS control, parsing of tts-text messages with marks,
//         edge cases (empty input, missing fields, special characters, CJK text).
//
// @coordinates-with: FoliateTTSAdapter.swift

import Testing
import Foundation
@testable import vreader

// MARK: - initTTSJS

@Suite("FoliateTTSAdapter - initTTSJS")
struct InitTTSJSTests {

    @Test("contains readerAPI.initTTS call with word granularity")
    func wordGranularity() {
        let js = FoliateTTSAdapter.initTTSJS(granularity: "word")
        #expect(js.contains("readerAPI.initTTS"))
        #expect(js.contains("word"))
    }

    @Test("contains readerAPI.initTTS call with sentence granularity")
    func sentenceGranularity() {
        let js = FoliateTTSAdapter.initTTSJS(granularity: "sentence")
        #expect(js.contains("readerAPI.initTTS"))
        #expect(js.contains("sentence"))
    }

    @Test("passes granularity as a quoted string parameter")
    func granularityQuoted() {
        let js = FoliateTTSAdapter.initTTSJS(granularity: "word")
        #expect(js.contains("'word'") || js.contains("\"word\""))
    }

    @Test("empty granularity string is passed through")
    func emptyGranularity() {
        let js = FoliateTTSAdapter.initTTSJS(granularity: "")
        #expect(js.contains("readerAPI.initTTS"))
    }
}

// MARK: - startTTSJS

@Suite("FoliateTTSAdapter - startTTSJS")
struct StartTTSJSTests {

    @Test("contains readerAPI.tts.start call")
    func containsStartCall() {
        let js = FoliateTTSAdapter.startTTSJS()
        #expect(js.contains("readerAPI.tts.start"))
    }

    @Test("returns a non-empty string")
    func nonEmpty() {
        let js = FoliateTTSAdapter.startTTSJS()
        #expect(!js.isEmpty)
    }
}

// MARK: - nextTTSJS

@Suite("FoliateTTSAdapter - nextTTSJS")
struct NextTTSJSTests {

    @Test("contains readerAPI.tts.next call")
    func containsNextCall() {
        let js = FoliateTTSAdapter.nextTTSJS()
        #expect(js.contains("readerAPI.tts.next"))
    }
}

// MARK: - prevTTSJS

@Suite("FoliateTTSAdapter - prevTTSJS")
struct PrevTTSJSTests {

    @Test("contains readerAPI.tts.prev call")
    func containsPrevCall() {
        let js = FoliateTTSAdapter.prevTTSJS()
        #expect(js.contains("readerAPI.tts.prev"))
    }
}

// MARK: - setMarkJS

@Suite("FoliateTTSAdapter - setMarkJS")
struct SetMarkJSTests {

    @Test("contains readerAPI.tts.setMark call with mark value")
    func containsSetMarkCall() {
        let js = FoliateTTSAdapter.setMarkJS(mark: "3")
        #expect(js.contains("readerAPI.tts.setMark"))
        #expect(js.contains("3"))
    }

    @Test("escapes mark with quotes")
    func markIsQuoted() {
        let js = FoliateTTSAdapter.setMarkJS(mark: "42")
        // Mark should be passed as a quoted string argument
        #expect(js.contains("'42'") || js.contains("\"42\""))
    }

    @Test("handles mark containing single quote by escaping")
    func markWithSingleQuote() {
        let js = FoliateTTSAdapter.setMarkJS(mark: "it's")
        #expect(js.contains("readerAPI.tts.setMark"))
        // Should not produce broken JS — the quote must be escaped
        #expect(!js.contains("'it's'"))
    }

    @Test("handles mark containing backslash")
    func markWithBackslash() {
        let js = FoliateTTSAdapter.setMarkJS(mark: "a\\b")
        #expect(js.contains("readerAPI.tts.setMark"))
        // Backslash should be escaped in the JS string
        #expect(js.contains("\\\\"))
    }

    @Test("empty mark string still produces valid call")
    func emptyMark() {
        let js = FoliateTTSAdapter.setMarkJS(mark: "")
        #expect(js.contains("readerAPI.tts.setMark"))
    }

    @Test("numeric mark is passed as string")
    func numericMark() {
        let js = FoliateTTSAdapter.setMarkJS(mark: "0")
        #expect(js.contains("'0'") || js.contains("\"0\""))
    }
}

// MARK: - parseTTSBlock

@Suite("FoliateTTSAdapter - parseTTSBlock")
struct ParseTTSBlockTests {

    @Test("valid dict with text and marks returns FoliateTTSBlock")
    func validDictWithMarks() {
        let body: [String: Any] = [
            "text": "Hello world from the book",
            "marks": [
                ["name": "0", "start": 0, "end": 5] as [String: Any],
                ["name": "1", "start": 6, "end": 11] as [String: Any],
                ["name": "2", "start": 12, "end": 16] as [String: Any],
                ["name": "3", "start": 17, "end": 20] as [String: Any],
                ["name": "4", "start": 21, "end": 25] as [String: Any],
            ] as [[String: Any]],
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block != nil)
        #expect(block?.text == "Hello world from the book")
        #expect(block?.marks.count == 5)
        #expect(block?.marks[0].name == "0")
        #expect(block?.marks[0].start == 0)
        #expect(block?.marks[0].end == 5)
        #expect(block?.marks[4].name == "4")
        #expect(block?.marks[4].start == 21)
        #expect(block?.marks[4].end == 25)
    }

    @Test("valid dict with empty marks array returns block with no marks")
    func emptyMarks() {
        let body: [String: Any] = [
            "text": "A paragraph without word boundaries.",
            "marks": [] as [[String: Any]],
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block != nil)
        #expect(block?.text == "A paragraph without word boundaries.")
        #expect(block?.marks.isEmpty == true)
    }

    @Test("missing text returns nil")
    func missingText() {
        let body: [String: Any] = [
            "marks": [
                ["name": "0", "start": 0, "end": 5] as [String: Any],
            ] as [[String: Any]],
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block == nil)
    }

    @Test("missing marks key returns block with empty marks")
    func missingMarksKey() {
        let body: [String: Any] = [
            "text": "Text without marks key",
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block != nil)
        #expect(block?.text == "Text without marks key")
        #expect(block?.marks.isEmpty == true)
    }

    @Test("non-dict body returns nil")
    func nonDictBody() {
        let block = FoliateTTSAdapter.parseTTSBlock("just a string")
        #expect(block == nil)
    }

    @Test("non-dict body as array returns nil")
    func arrayBody() {
        let block = FoliateTTSAdapter.parseTTSBlock([1, 2, 3])
        #expect(block == nil)
    }

    @Test("mark ordering is preserved")
    func markOrderPreserved() {
        let body: [String: Any] = [
            "text": "abc def ghi",
            "marks": [
                ["name": "2", "start": 8, "end": 11] as [String: Any],
                ["name": "0", "start": 0, "end": 3] as [String: Any],
                ["name": "1", "start": 4, "end": 7] as [String: Any],
            ] as [[String: Any]],
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block != nil)
        // Marks should preserve input order (not sort by start)
        #expect(block?.marks[0].name == "2")
        #expect(block?.marks[1].name == "0")
        #expect(block?.marks[2].name == "1")
    }

    @Test("single mark in array parses correctly")
    func singleMark() {
        let body: [String: Any] = [
            "text": "hello",
            "marks": [
                ["name": "0", "start": 0, "end": 5] as [String: Any],
            ] as [[String: Any]],
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block != nil)
        #expect(block?.marks.count == 1)
        #expect(block?.marks[0].name == "0")
        #expect(block?.marks[0].start == 0)
        #expect(block?.marks[0].end == 5)
    }

    @Test("mark with missing name is skipped")
    func markMissingName() {
        let body: [String: Any] = [
            "text": "hello world",
            "marks": [
                ["start": 0, "end": 5] as [String: Any],
                ["name": "1", "start": 6, "end": 11] as [String: Any],
            ] as [[String: Any]],
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block != nil)
        #expect(block?.marks.count == 1)
        #expect(block?.marks[0].name == "1")
    }

    @Test("mark with missing start is skipped")
    func markMissingStart() {
        let body: [String: Any] = [
            "text": "hello world",
            "marks": [
                ["name": "0", "end": 5] as [String: Any],
                ["name": "1", "start": 6, "end": 11] as [String: Any],
            ] as [[String: Any]],
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block != nil)
        #expect(block?.marks.count == 1)
        #expect(block?.marks[0].name == "1")
    }

    @Test("mark with missing end is skipped")
    func markMissingEnd() {
        let body: [String: Any] = [
            "text": "hello world",
            "marks": [
                ["name": "0", "start": 0] as [String: Any],
                ["name": "1", "start": 6, "end": 11] as [String: Any],
            ] as [[String: Any]],
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block != nil)
        #expect(block?.marks.count == 1)
        #expect(block?.marks[0].name == "1")
    }

    @Test("CJK text in block parses correctly")
    func cjkText() {
        let body: [String: Any] = [
            "text": "今天天气很好",
            "marks": [
                ["name": "0", "start": 0, "end": 2] as [String: Any],
                ["name": "1", "start": 2, "end": 4] as [String: Any],
                ["name": "2", "start": 4, "end": 6] as [String: Any],
            ] as [[String: Any]],
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block != nil)
        #expect(block?.text == "今天天气很好")
        #expect(block?.marks.count == 3)
    }

    @Test("text as non-string type returns nil")
    func textWrongType() {
        let body: [String: Any] = [
            "text": 12345,
            "marks": [] as [[String: Any]],
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block == nil)
    }

    @Test("marks as non-array type returns block with empty marks")
    func marksWrongType() {
        let body: [String: Any] = [
            "text": "hello",
            "marks": "not an array",
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block != nil)
        #expect(block?.marks.isEmpty == true)
    }

    @Test("empty dict returns nil")
    func emptyDict() {
        let body: [String: Any] = [:]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block == nil)
    }

    @Test("extra unexpected keys do not cause failure")
    func extraKeys() {
        let body: [String: Any] = [
            "text": "hello world",
            "marks": [] as [[String: Any]],
            "ssml": "<speak>old format</speak>",
            "language": "en",
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block != nil)
        #expect(block?.text == "hello world")
    }

    @Test("mark with Int-typed start and end parses correctly")
    func markIntTypes() {
        let body: [String: Any] = [
            "text": "hello",
            "marks": [
                ["name": "0", "start": 0 as Int, "end": 5 as Int] as [String: Any],
            ] as [[String: Any]],
        ]
        let block = FoliateTTSAdapter.parseTTSBlock(body)
        #expect(block != nil)
        #expect(block?.marks.count == 1)
        #expect(block?.marks[0].start == 0)
        #expect(block?.marks[0].end == 5)
    }
}

// MARK: - Equatable conformance

@Suite("FoliateTTSAdapter - types")
struct TypeTests {

    @Test("FoliateTTSBlock conforms to Equatable")
    func blockEquatable() {
        let marks = [FoliateTTSMark(name: "0", start: 0, end: 5)]
        let a = FoliateTTSBlock(text: "hello", marks: marks)
        let b = FoliateTTSBlock(text: "hello", marks: marks)
        #expect(a == b)
    }

    @Test("FoliateTTSBlock with different text is not equal")
    func blockNotEqual() {
        let marks = [FoliateTTSMark(name: "0", start: 0, end: 5)]
        let a = FoliateTTSBlock(text: "hello", marks: marks)
        let b = FoliateTTSBlock(text: "world", marks: marks)
        #expect(a != b)
    }

    @Test("FoliateTTSMark conforms to Equatable")
    func markEquatable() {
        let a = FoliateTTSMark(name: "0", start: 0, end: 5)
        let b = FoliateTTSMark(name: "0", start: 0, end: 5)
        #expect(a == b)
    }

    @Test("FoliateTTSMark with different name is not equal")
    func markNotEqual() {
        let a = FoliateTTSMark(name: "0", start: 0, end: 5)
        let b = FoliateTTSMark(name: "1", start: 0, end: 5)
        #expect(a != b)
    }
}
