// Purpose: Translates highlight ranges between global (DB) and chapter-local
// (display) coordinates. Used at the TXTReaderContainerView boundary to adapt
// persisted highlights for chapter display.
//
// Key decisions:
// - Pure functions (enum namespace) — no state, no MainActor.
// - All offsets are UTF-16 code units matching NSString/UIKit conventions.
// - Highlights spanning chapter boundaries are clipped to the chapter range.
// - Invalid inputs (out-of-bounds index, negative start, zero-length) return
//   empty results rather than crashing.
//
// @coordinates-with: TXTChapter.swift, ReaderNotificationModifier.swift,
//   TXTReaderContainerView.swift

import Foundation

/// Translates highlight ranges between global (DB) and chapter-local (display) coordinates.
/// Used at the TXTReaderContainerView boundary to adapt persisted highlights for chapter display.
enum TXTChapterHighlightHelper {

    /// Filters and translates persisted highlight ranges (global UTF-16) to chapter-local ranges.
    /// Only returns highlights that fall within the given chapter.
    static func highlightsForChapter(
        chapterIndex: Int,
        chapters: [TXTChapter],
        persistedGlobalRanges: [NSRange]
    ) -> [NSRange] {
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return [] }
        let chapter = chapters[chapterIndex]
        guard chapter.globalStartUTF16 >= 0, chapter.textLengthUTF16 > 0 else { return [] }

        let chapterStart = chapter.globalStartUTF16
        let chapterEnd = chapterStart + chapter.textLengthUTF16

        return persistedGlobalRanges.compactMap { globalRange in
            let rangeStart = globalRange.location
            let rangeEnd = globalRange.location + globalRange.length

            // Skip if entirely outside this chapter
            guard rangeEnd > chapterStart, rangeStart < chapterEnd else { return nil }

            // Clip to chapter boundaries
            let clippedStart = max(rangeStart, chapterStart)
            let clippedEnd = min(rangeEnd, chapterEnd)

            // Translate to chapter-local
            return NSRange(
                location: clippedStart - chapterStart,
                length: clippedEnd - clippedStart
            )
        }
    }

    /// Translates a chapter-local NSRange (from new highlight creation) to global.
    static func toGlobalRange(
        localRange: NSRange,
        chapterIndex: Int,
        chapters: [TXTChapter]
    ) -> NSRange? {
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return nil }
        let chapter = chapters[chapterIndex]
        guard chapter.globalStartUTF16 >= 0 else { return nil }
        return NSRange(
            location: localRange.location + chapter.globalStartUTF16,
            length: localRange.length
        )
    }

    /// Translates a global scroll offset to chapter-local for bridge navigation.
    static func toChapterLocalOffset(
        globalUTF16: Int,
        chapterIndex: Int,
        chapters: [TXTChapter]
    ) -> Int {
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return 0 }
        let chapter = chapters[chapterIndex]
        guard chapter.globalStartUTF16 >= 0 else { return 0 }
        return max(0, globalUTF16 - chapter.globalStartUTF16)
    }
}
