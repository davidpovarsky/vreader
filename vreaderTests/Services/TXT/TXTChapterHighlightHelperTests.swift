// Purpose: Tests for TXTChapterHighlightHelper — offset translation between
// global (DB) and chapter-local (display) coordinates.

import Testing
import Foundation
@testable import vreader

@Suite("TXTChapterHighlightHelper")
struct TXTChapterHighlightHelperTests {

    // MARK: - Fixtures

    /// Three chapters: [0..100), [100..250), [250..400)
    private static let chapters = [
        TXTChapter(index: 0, title: "Chapter 1", startByte: 0, endByte: 200, globalStartUTF16: 0, textLengthUTF16: 100),
        TXTChapter(index: 1, title: "Chapter 2", startByte: 200, endByte: 500, globalStartUTF16: 100, textLengthUTF16: 150),
        TXTChapter(index: 2, title: "Chapter 3", startByte: 500, endByte: 800, globalStartUTF16: 250, textLengthUTF16: 150),
    ]

    // MARK: - highlightsForChapter

    @Test("highlights within chapter — returns correctly translated ranges")
    func testHighlightsWithinChapter() {
        // Highlight at global [110, 140) should map to local [10, 40) in chapter 2
        let globalRanges = [NSRange(location: 110, length: 30)]
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: globalRanges
        )
        #expect(result.count == 1)
        #expect(result[0] == NSRange(location: 10, length: 30))
    }

    @Test("highlights outside chapter — returns empty")
    func testHighlightsOutsideChapter() {
        // Highlight at global [0, 50) is in chapter 1, not chapter 2
        let globalRanges = [NSRange(location: 0, length: 50)]
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: globalRanges
        )
        #expect(result.isEmpty)
    }

    @Test("highlight spanning chapter boundary — clips to chapter bounds")
    func testHighlightSpanningChapterBoundary() {
        // Highlight at global [80, 130) spans chapters 1 and 2.
        // For chapter 1 [0..100): clipped to [80, 100) → local [80, 20len)
        // For chapter 2 [100..250): clipped to [100, 130) → local [0, 30)
        let globalRanges = [NSRange(location: 80, length: 50)]

        let ch1Result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 0,
            chapters: Self.chapters,
            persistedGlobalRanges: globalRanges
        )
        #expect(ch1Result.count == 1)
        #expect(ch1Result[0] == NSRange(location: 80, length: 20))

        let ch2Result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: globalRanges
        )
        #expect(ch2Result.count == 1)
        #expect(ch2Result[0] == NSRange(location: 0, length: 30))
    }

    @Test("multiple highlights — filters and translates correctly")
    func testMultipleHighlights() {
        // Mix of highlights: one in chapter 2, one outside, one spanning
        let globalRanges = [
            NSRange(location: 110, length: 10),  // fully in chapter 2
            NSRange(location: 300, length: 20),  // fully in chapter 3
            NSRange(location: 240, length: 30),  // spans chapters 2 and 3
        ]

        let ch2Result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: globalRanges
        )
        // First: [110,120) → local [10,10)
        // Second: [300,320) entirely in ch3 → skipped
        // Third: [240,270) spans ch2[100..250) → clipped [240,250) → local [140, 10)
        #expect(ch2Result.count == 2)
        #expect(ch2Result[0] == NSRange(location: 10, length: 10))
        #expect(ch2Result[1] == NSRange(location: 140, length: 10))
    }

    @Test("empty persisted ranges — returns empty")
    func testEmptyPersistedRanges() {
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 0,
            chapters: Self.chapters,
            persistedGlobalRanges: []
        )
        #expect(result.isEmpty)
    }

    @Test("chapter index out of bounds — returns empty")
    func testChapterIndexOutOfBounds() {
        let globalRanges = [NSRange(location: 10, length: 20)]
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 99,
            chapters: Self.chapters,
            persistedGlobalRanges: globalRanges
        )
        #expect(result.isEmpty)
    }

    @Test("empty chapters array — returns empty")
    func testEmptyChaptersArray() {
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 0,
            chapters: [],
            persistedGlobalRanges: [NSRange(location: 0, length: 10)]
        )
        #expect(result.isEmpty)
    }

    @Test("chapter with zero text length — returns empty")
    func testZeroLengthChapter() {
        let chapters = [TXTChapter(index: 0, title: "Empty", startByte: 0, endByte: 0, globalStartUTF16: 0, textLengthUTF16: 0)]
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 0,
            chapters: chapters,
            persistedGlobalRanges: [NSRange(location: 0, length: 10)]
        )
        #expect(result.isEmpty)
    }

    @Test("chapter with negative globalStartUTF16 — returns empty")
    func testNegativeGlobalStart() {
        let chapters = [TXTChapter(index: 0, title: "Bad", startByte: 0, endByte: 200, globalStartUTF16: -1, textLengthUTF16: 100)]
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 0,
            chapters: chapters,
            persistedGlobalRanges: [NSRange(location: 0, length: 10)]
        )
        #expect(result.isEmpty)
    }

    @Test("highlight at exact chapter start boundary")
    func testHighlightAtExactStart() {
        // Highlight starting at exact start of chapter 2 (offset 100)
        let globalRanges = [NSRange(location: 100, length: 10)]
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: globalRanges
        )
        #expect(result.count == 1)
        #expect(result[0] == NSRange(location: 0, length: 10))
    }

    @Test("highlight at exact chapter end boundary — not included")
    func testHighlightAtExactEnd() {
        // Highlight starting at offset 250 (chapter 2 ends at 250)
        let globalRanges = [NSRange(location: 250, length: 10)]
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: globalRanges
        )
        #expect(result.isEmpty)
    }

    // MARK: - toGlobalRange

    @Test("toGlobalRange — correct translation")
    func testToGlobalRange() {
        let localRange = NSRange(location: 10, length: 30)
        let result = TXTChapterHighlightHelper.toGlobalRange(
            localRange: localRange,
            chapterIndex: 1,
            chapters: Self.chapters
        )
        #expect(result == NSRange(location: 110, length: 30))
    }

    @Test("toGlobalRange — chapter index out of bounds returns nil")
    func testToGlobalRangeOutOfBounds() {
        let result = TXTChapterHighlightHelper.toGlobalRange(
            localRange: NSRange(location: 0, length: 10),
            chapterIndex: 99,
            chapters: Self.chapters
        )
        #expect(result == nil)
    }

    @Test("toGlobalRange — negative globalStartUTF16 returns nil")
    func testToGlobalRangeNegativeStart() {
        let chapters = [TXTChapter(index: 0, title: "Bad", startByte: 0, endByte: 200, globalStartUTF16: -1, textLengthUTF16: 100)]
        let result = TXTChapterHighlightHelper.toGlobalRange(
            localRange: NSRange(location: 0, length: 10),
            chapterIndex: 0,
            chapters: chapters
        )
        #expect(result == nil)
    }

    @Test("toGlobalRange — first chapter (offset 0)")
    func testToGlobalRangeFirstChapter() {
        let localRange = NSRange(location: 5, length: 20)
        let result = TXTChapterHighlightHelper.toGlobalRange(
            localRange: localRange,
            chapterIndex: 0,
            chapters: Self.chapters
        )
        #expect(result == NSRange(location: 5, length: 20))
    }

    // MARK: - toChapterLocalOffset

    @Test("toChapterLocalOffset — correct offset")
    func testToChapterLocalOffset() {
        let result = TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: 130,
            chapterIndex: 1,
            chapters: Self.chapters
        )
        #expect(result == 30)
    }

    @Test("toChapterLocalOffset — offset at chapter start")
    func testToChapterLocalOffsetAtStart() {
        let result = TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: 100,
            chapterIndex: 1,
            chapters: Self.chapters
        )
        #expect(result == 0)
    }

    @Test("toChapterLocalOffset — offset before chapter returns 0")
    func testToChapterLocalOffsetBeforeChapter() {
        let result = TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: 50,
            chapterIndex: 1,
            chapters: Self.chapters
        )
        #expect(result == 0)
    }

    @Test("toChapterLocalOffset — chapter index out of bounds returns 0")
    func testToChapterLocalOffsetOutOfBounds() {
        let result = TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: 130,
            chapterIndex: 99,
            chapters: Self.chapters
        )
        #expect(result == 0)
    }

    @Test("toChapterLocalOffset — negative globalStartUTF16 returns 0")
    func testToChapterLocalOffsetNegativeStart() {
        let chapters = [TXTChapter(index: 0, title: "Bad", startByte: 0, endByte: 200, globalStartUTF16: -1, textLengthUTF16: 100)]
        let result = TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: 50,
            chapterIndex: 0,
            chapters: chapters
        )
        #expect(result == 0)
    }

    @Test("toChapterLocalOffset — empty chapters returns 0")
    func testToChapterLocalOffsetEmptyChapters() {
        let result = TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: 50,
            chapterIndex: 0,
            chapters: []
        )
        #expect(result == 0)
    }
}
