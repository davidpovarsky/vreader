// Purpose: Pure functions for calculating book-level reading progress when
// using chapter-based display. Decoupled from UI for testability.
//
// Key decisions:
// - All functions are static and side-effect-free.
// - Returns nil for invalid inputs (zero chapters, out-of-bounds index).
// - scrollFraction is clamped to 0...1.
// - Progress = (completedChapters + fractionOfCurrentChapter) / totalChapters.
//
// @coordinates-with: TXTReaderContainerView.swift, TXTReaderViewModel.swift

import Foundation

/// Calculates book-level progress from chapter index and scroll position.
enum ChapterProgressCalculator {

    /// Computes book-level progress (0.0 to 1.0) from chapter navigation state.
    ///
    /// - Parameters:
    ///   - currentChapterIdx: Zero-based index of the current chapter.
    ///   - scrollFraction: Fraction scrolled through the current chapter (0.0 to 1.0).
    ///   - totalChapters: Total number of chapters in the book.
    /// - Returns: A value in 0.0...1.0, or nil if inputs are invalid.
    static func bookProgress(
        currentChapterIdx: Int,
        scrollFraction: Double,
        totalChapters: Int
    ) -> Double? {
        guard totalChapters > 0 else { return nil }
        guard currentChapterIdx >= 0, currentChapterIdx < totalChapters else { return nil }

        let clampedFraction = min(max(scrollFraction, 0), 1)
        let raw = (Double(currentChapterIdx) + clampedFraction) / Double(totalChapters)
        return min(max(raw, 0), 1)
    }

    /// Computes the chapter title to show in the "Next chapter" indicator.
    ///
    /// - Parameters:
    ///   - currentChapterIdx: Zero-based index of the current chapter.
    ///   - chapterIndex: The chapter index to look up titles from.
    /// - Returns: The next chapter's title, or nil if at the last chapter.
    static func nextChapterTitle(
        currentChapterIdx: Int,
        chapterIndex: TXTChapterIndex
    ) -> String? {
        let nextIdx = currentChapterIdx + 1
        guard nextIdx < chapterIndex.count else { return nil }
        let title = chapterIndex.title(at: nextIdx)
        return (title?.isEmpty ?? true) ? nil : title
    }

    /// Computes the chapter title to show in the "Previous chapter" indicator.
    ///
    /// - Parameters:
    ///   - currentChapterIdx: Zero-based index of the current chapter.
    ///   - chapterIndex: The chapter index to look up titles from.
    /// - Returns: The previous chapter's title, or nil if at the first chapter.
    static func previousChapterTitle(
        currentChapterIdx: Int,
        chapterIndex: TXTChapterIndex
    ) -> String? {
        let prevIdx = currentChapterIdx - 1
        guard prevIdx >= 0 else { return nil }
        let title = chapterIndex.title(at: prevIdx)
        return (title?.isEmpty ?? true) ? nil : title
    }
}
