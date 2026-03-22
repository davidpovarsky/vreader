// Purpose: Bidirectional translation between global UTF-16 offsets and
// chapter-local offsets. Uses O(log n) binary search for chapter lookup.
//
// Key decisions:
// - Pure functions (enum namespace) — no state, no actor isolation.
// - Requires globalStartUTF16 to be populated (>= 0) for search methods.
// - Returns nil for out-of-bounds, negative, or unpopulated offsets.
// - toLocalRange returns nil if range spans multiple chapters.
// - populateUTF16Offsets uses a caller-provided loader closure for decoding.
//
// @coordinates-with: TXTChapterTypes.swift, TXTChapterIndexStore.swift

import Foundation

/// Bidirectional translation between global UTF-16 offsets and chapter-local offsets.
enum TXTOffsetTranslator {

    /// A position within a specific chapter.
    struct ChapterLocalPosition: Equatable {
        let chapterIndex: Int
        let localOffsetUTF16: Int
    }

    // MARK: - Global → Local

    /// Global UTF-16 offset → chapter index + local offset. O(log n) binary search.
    /// Returns nil if offset is negative, beyond total length, or chapters is empty.
    static func toLocal(globalUTF16: Int, chapters: [TXTChapter]) -> ChapterLocalPosition? {
        guard let chIdx = chapterContaining(globalUTF16: globalUTF16, chapters: chapters) else {
            return nil
        }
        let chapter = chapters[chIdx]
        let local = globalUTF16 - chapter.globalStartUTF16
        return ChapterLocalPosition(chapterIndex: chIdx, localOffsetUTF16: local)
    }

    // MARK: - Local → Global

    /// Chapter index + local offset → global UTF-16 offset.
    /// Returns nil if chapterIndex is invalid or localUTF16 is out of chapter bounds.
    static func toGlobal(chapterIndex: Int, localUTF16: Int, chapters: [TXTChapter]) -> Int? {
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return nil }
        let chapter = chapters[chapterIndex]
        guard localUTF16 >= 0, localUTF16 < chapter.textLengthUTF16 else { return nil }
        return chapter.globalStartUTF16 + localUTF16
    }

    // MARK: - Range Translation

    /// Global NSRange → chapter-local NSRange. Returns nil if range spans chapters.
    static func toLocalRange(
        globalRange: NSRange,
        chapters: [TXTChapter]
    ) -> (chapterIndex: Int, localRange: NSRange)? {
        guard chapters.count > 0 else { return nil }

        let startOffset = globalRange.location
        // For zero-length ranges, start == end
        let endOffset = globalRange.location + max(globalRange.length - 1, 0)

        guard let startChapter = chapterContaining(globalUTF16: startOffset, chapters: chapters) else {
            return nil
        }

        // For non-zero-length ranges, check that the end is in the same chapter
        if globalRange.length > 0 {
            guard let endChapter = chapterContaining(globalUTF16: endOffset, chapters: chapters),
                  endChapter == startChapter else {
                return nil
            }
        }

        let localStart = startOffset - chapters[startChapter].globalStartUTF16
        return (chapterIndex: startChapter, localRange: NSRange(location: localStart, length: globalRange.length))
    }

    // MARK: - Binary Search

    /// Finds the chapter containing a global UTF-16 offset. O(log n).
    /// Returns nil if offset is negative, beyond end, or chapters is empty.
    static func chapterContaining(globalUTF16: Int, chapters: [TXTChapter]) -> Int? {
        guard !chapters.isEmpty, globalUTF16 >= 0 else { return nil }

        var lo = 0
        var hi = chapters.count - 1

        while lo <= hi {
            let mid = lo + (hi - lo) / 2
            let chapter = chapters[mid]
            let chapterStart = chapter.globalStartUTF16
            let chapterEnd = chapterStart + chapter.textLengthUTF16

            if globalUTF16 < chapterStart {
                hi = mid - 1
            } else if globalUTF16 >= chapterEnd {
                lo = mid + 1
            } else {
                // chapterStart <= globalUTF16 < chapterEnd
                return mid
            }
        }

        return nil
    }

    // MARK: - UTF-16 Offset Population

    /// Populates globalStartUTF16 and textLengthUTF16 for all chapters.
    /// Call this after building the index by decoding each chapter via the loader.
    static func populateUTF16Offsets(
        chapters: inout [TXTChapter],
        loader: (TXTChapter) throws -> String
    ) rethrows {
        var cumulativeOffset = 0
        for i in chapters.indices {
            chapters[i].globalStartUTF16 = cumulativeOffset
            let text = try loader(chapters[i])
            let utf16Length = (text as NSString).length
            chapters[i].textLengthUTF16 = utf16Length
            cumulativeOffset += utf16Length
        }
    }
}
