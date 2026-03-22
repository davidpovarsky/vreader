// Purpose: Tests for ReflowableTextSource protocol and its TXT/MD adapters.
// Validates segment generation, UTF-16 offset correctness, and edge cases.

import Testing
import Foundation
@testable import vreader

// MARK: - TXTReflowableTextSource Tests

@Suite("TXTReflowableTextSource")
struct TXTReflowableTextSourceTests {

    @Test func txtSource_segments_returnsFullText_asSingleSegment() {
        let text = "Hello, world!"
        let source = TXTReflowableTextSource(textContent: text)
        #expect(source.segments.count == 1)
        #expect(source.segments.first?.text == text)
    }

    @Test func txtSource_fullText_matchesOriginal() {
        let text = "Line one.\nLine two.\nLine three."
        let source = TXTReflowableTextSource(textContent: text)
        let concatenated = source.segments.map(\.text).joined()
        #expect(concatenated == text)
        #expect(source.fullText == text)
    }

    @Test func txtSource_segmentAtOffset_returnsCorrectSegment() {
        let text = "Hello, world!"
        let source = TXTReflowableTextSource(textContent: text)
        let segment = source.segmentContaining(offsetUTF16: 3)
        #expect(segment != nil)
        #expect(segment?.text == text)
        #expect(segment?.startOffsetUTF16 == 0)
    }

    @Test func txtSource_emptyText_returnsEmptySegments() {
        let source = TXTReflowableTextSource(textContent: "")
        #expect(source.segments.isEmpty)
        #expect(source.totalLengthUTF16 == 0)
        #expect(source.fullText == "")
    }

    @Test func txtSource_cjkText_utf16OffsetsCorrect() {
        let text = "你好世界"  // 4 CJK chars, each 1 UTF-16 code unit = 4 total
        let source = TXTReflowableTextSource(textContent: text)
        #expect(source.totalLengthUTF16 == text.utf16.count)
        let segment = source.segmentContaining(offsetUTF16: 2)
        #expect(segment != nil)
        #expect(segment?.lengthUTF16 == text.utf16.count)
    }

    @Test func txtSource_totalLengthUTF16_matchesStringLength() {
        let text = "Hello 🌍 World"
        let source = TXTReflowableTextSource(textContent: text)
        #expect(source.totalLengthUTF16 == text.utf16.count)
    }

    @Test func txtSource_segmentAtOffset_zero_returnsFirstSegment() {
        let text = "Some content"
        let source = TXTReflowableTextSource(textContent: text)
        let segment = source.segmentContaining(offsetUTF16: 0)
        #expect(segment != nil)
        #expect(segment?.startOffsetUTF16 == 0)
    }

    @Test func txtSource_segmentAtOffset_negative_returnsNil() {
        let text = "Some content"
        let source = TXTReflowableTextSource(textContent: text)
        let segment = source.segmentContaining(offsetUTF16: -1)
        #expect(segment == nil)
    }

    @Test func txtSource_segmentAtOffset_pastEnd_returnsNil() {
        let text = "Hello"
        let source = TXTReflowableTextSource(textContent: text)
        let segment = source.segmentContaining(offsetUTF16: text.utf16.count)
        #expect(segment == nil, "Offset == totalLength is past-end, should return nil")
    }

    @Test func txtSource_emojiSurrogatePairs_utf16CorrectLength() {
        // Emoji with surrogate pairs: each emoji flag is 4 UTF-16 code units
        let text = "🇯🇵🇺🇸"
        let source = TXTReflowableTextSource(textContent: text)
        #expect(source.totalLengthUTF16 == text.utf16.count)
        #expect(source.segments.count == 1)
        #expect(source.segments.first?.lengthUTF16 == text.utf16.count)
    }
}

// MARK: - MDReflowableTextSource Tests

@Suite("MDReflowableTextSource")
struct MDReflowableTextSourceTests {

    @Test func mdSource_segments_returnsRenderedText() {
        let rendered = "Rendered markdown content"
        let source = MDReflowableTextSource(renderedText: rendered)
        #expect(source.segments.count == 1)
        #expect(source.segments.first?.text == rendered)
    }

    @Test func mdSource_emptyDocument_returnsEmptySegments() {
        let source = MDReflowableTextSource(renderedText: "")
        #expect(source.segments.isEmpty)
        #expect(source.totalLengthUTF16 == 0)
        #expect(source.fullText == "")
    }

    @Test func mdSource_segmentAtOffset_returnsCorrectSegment() {
        let rendered = "Some rendered text"
        let source = MDReflowableTextSource(renderedText: rendered)
        let segment = source.segmentContaining(offsetUTF16: 5)
        #expect(segment != nil)
        #expect(segment?.text == rendered)
    }

    @Test func mdSource_fullText_matchesRendered() {
        let rendered = "# Heading\nParagraph text."
        let source = MDReflowableTextSource(renderedText: rendered)
        #expect(source.fullText == rendered)
        let concatenated = source.segments.map(\.text).joined()
        #expect(concatenated == rendered)
    }

    @Test func mdSource_cjkText_utf16Correct() {
        let rendered = "中文Markdown内容"
        let source = MDReflowableTextSource(renderedText: rendered)
        #expect(source.totalLengthUTF16 == rendered.utf16.count)
    }

    @Test func mdSource_segmentAtOffset_pastEnd_returnsNil() {
        let rendered = "Hello"
        let source = MDReflowableTextSource(renderedText: rendered)
        let segment = source.segmentContaining(offsetUTF16: rendered.utf16.count)
        #expect(segment == nil)
    }
}

// MARK: - Segment Offset Contiguity Tests

@Suite("TextSegment offset contiguity")
struct TextSegmentContiguityTests {

    @Test func segmentOffsets_contiguous_andSumToTotal_txt() {
        let text = "Hello, world! This is a test."
        let source = TXTReflowableTextSource(textContent: text)
        assertContiguousSegments(source: source)
    }

    @Test func segmentOffsets_contiguous_andSumToTotal_md() {
        let text = "# Title\n\nBody content here."
        let source = MDReflowableTextSource(renderedText: text)
        assertContiguousSegments(source: source)
    }

    @Test func segmentOffsets_contiguous_emptySource_txt() {
        let source = TXTReflowableTextSource(textContent: "")
        assertContiguousSegments(source: source)
    }

    @Test func segmentOffsets_contiguous_emptySource_md() {
        let source = MDReflowableTextSource(renderedText: "")
        assertContiguousSegments(source: source)
    }

    @Test func segmentOffsets_contiguous_cjk() {
        let text = "你好世界。这是一段中文文本，用于测试分段偏移量的正确性。"
        let source = TXTReflowableTextSource(textContent: text)
        assertContiguousSegments(source: source)
    }

    @Test func segmentOffsets_contiguous_emoji() {
        let text = "Hello 🎉🎊🎈 World 🌍"
        let source = TXTReflowableTextSource(textContent: text)
        assertContiguousSegments(source: source)
    }

    // MARK: - Helper

    private func assertContiguousSegments(source: some ReflowableTextSource) {
        let segments = source.segments

        if segments.isEmpty {
            #expect(source.totalLengthUTF16 == 0)
            return
        }

        // First segment starts at 0
        #expect(segments.first!.startOffsetUTF16 == 0,
                "First segment must start at offset 0")

        // Each segment starts where the previous one ends (contiguous, no gaps)
        for i in 1..<segments.count {
            let prev = segments[i - 1]
            let curr = segments[i]
            let expectedStart = prev.startOffsetUTF16 + prev.lengthUTF16
            #expect(curr.startOffsetUTF16 == expectedStart,
                    "Segment \(i) should start at \(expectedStart), got \(curr.startOffsetUTF16)")
        }

        // Sum of all segment lengths equals totalLengthUTF16
        let totalFromSegments = segments.reduce(0) { $0 + $1.lengthUTF16 }
        #expect(totalFromSegments == source.totalLengthUTF16,
                "Sum of segment lengths (\(totalFromSegments)) must equal totalLengthUTF16 (\(source.totalLengthUTF16))")
    }
}
