// Purpose: Result type for unified EPUB loading (Issue 10).
// Tracks loaded text/attributed text, skipped chapter count, and total chapter count.
// Used by ReaderContainerView.loadUnifiedEPUBContent() to report loading quality.
//
// @coordinates-with ReaderContainerView.swift, EPUBTextStripper.swift

import Foundation

/// Captures the result of loading EPUB chapters into the unified reflow engine.
struct UnifiedEPUBLoadResult {
    /// The combined plain text from all loaded chapters, or nil if all failed.
    let text: String?
    /// The combined attributed text from all loaded chapters, or nil if all failed.
    let attributedText: NSAttributedString?
    /// Number of chapters that could not be loaded (failed to read or parse).
    let skippedChapterCount: Int
    /// Total number of spine chapters in the EPUB.
    let totalChapterCount: Int

    /// Whether any chapters were skipped during loading.
    var hasSkippedChapters: Bool {
        skippedChapterCount > 0
    }

    /// Whether all chapters failed to load (book is unreadable in unified mode).
    var allChaptersFailed: Bool {
        totalChapterCount == 0 || skippedChapterCount >= totalChapterCount
    }

    /// Warning message for partial loading, or nil if no chapters were skipped.
    var warningMessage: String? {
        guard hasSkippedChapters, !allChaptersFailed else { return nil }
        return "\(skippedChapterCount) of \(totalChapterCount) chapters could not be loaded"
    }

    /// Error message when all chapters failed, or nil otherwise.
    var errorMessage: String? {
        guard allChaptersFailed, totalChapterCount > 0 else { return nil }
        return "All \(totalChapterCount) chapters failed to load"
    }
}
