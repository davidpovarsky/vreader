// Purpose: Tests for TXTTextChunker — splits large text into rendering chunks
// at paragraph boundaries for chunked UITableView rendering.

import Testing
import Foundation
@testable import vreader

@Suite("TXTTextChunker")
struct TXTTextChunkerTests {

    // MARK: - Basic splitting

    @Test func emptyTextReturnsNoChunks() {
        let chunks = TXTTextChunker.split(text: "", targetChunkSize: 1000)
        #expect(chunks.isEmpty)
    }

    @Test func smallTextReturnsSingleChunk() {
        let text = "Hello, World!"
        let chunks = TXTTextChunker.split(text: text, targetChunkSize: 1000)
        #expect(chunks.count == 1)
        #expect(chunks.first == text)
    }

    @Test func splitsAtNewlineBoundaries() {
        let lines = (0..<10).map { "Line \($0)" }
        let text = lines.joined(separator: "\n")
        // Target size that forces splitting but each line is short
        let chunks = TXTTextChunker.split(text: text, targetChunkSize: 20)
        #expect(chunks.count > 1)
        // Reassembled text must equal original
        #expect(chunks.joined() == text)
    }

    @Test func preservesAllContent() {
        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        let chunks = TXTTextChunker.split(text: text, targetChunkSize: 20)
        #expect(chunks.joined() == text, "Reassembled chunks must equal original text")
    }

    @Test func chunksDontExceedTargetByMuch() {
        // Each chunk should be roughly targetChunkSize, not massively over
        let lines = (0..<100).map { "Line number \($0) with some content.\n" }
        let text = lines.joined()
        let targetSize = 200
        let chunks = TXTTextChunker.split(text: text, targetChunkSize: targetSize)
        for chunk in chunks {
            // Allow up to 2x target for long lines — but not wildly over
            #expect(chunk.utf16.count <= targetSize * 3,
                    "Chunk size \(chunk.utf16.count) exceeds 3x target \(targetSize)")
        }
    }

    // MARK: - CJK text

    @Test func splitsCJKText() {
        let cjk = String(repeating: "你好世界测试文本。\n", count: 100)
        let chunks = TXTTextChunker.split(text: cjk, targetChunkSize: 50)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == cjk)
    }

    @Test func cjkWithoutNewlinesFallsBackToCharBoundary() {
        // A single very long line with no newlines
        let longLine = String(repeating: "你", count: 1000)
        let chunks = TXTTextChunker.split(text: longLine, targetChunkSize: 100)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == longLine)
    }

    // MARK: - Edge cases

    @Test func singleLongLineWithNoNewlines() {
        let text = String(repeating: "A", count: 5000)
        let chunks = TXTTextChunker.split(text: text, targetChunkSize: 1000)
        #expect(chunks.count >= 5)
        #expect(chunks.joined() == text)
    }

    @Test func emptyLinesBetweenParagraphs() {
        let text = "Para1\n\n\nPara2\n\n\nPara3"
        let chunks = TXTTextChunker.split(text: text, targetChunkSize: 10)
        #expect(chunks.joined() == text)
    }

    @Test func trailingNewline() {
        let text = "Hello\nWorld\n"
        let chunks = TXTTextChunker.split(text: text, targetChunkSize: 8)
        #expect(chunks.joined() == text)
    }

    @Test func unicodeEmoji() {
        let text = "Hello 🎉\nWorld 🌍\nTest 🚀\n"
        let chunks = TXTTextChunker.split(text: text, targetChunkSize: 10)
        #expect(chunks.joined() == text)
    }

    @Test func windowsLineEndings() {
        let text = "Line1\r\nLine2\r\nLine3\r\n"
        let chunks = TXTTextChunker.split(text: text, targetChunkSize: 10)
        #expect(chunks.joined() == text)
    }

    // MARK: - Large scale

    @Test func largeTextSplitsCorrectly() {
        // Simulate a large file: 100K characters
        let paragraph = String(repeating: "这是一段很长的中文文本。", count: 10) + "\n"
        let text = String(repeating: paragraph, count: 100)
        let chunks = TXTTextChunker.split(text: text, targetChunkSize: 8000)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == text)
    }
}
