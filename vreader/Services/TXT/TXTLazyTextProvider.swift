// Purpose: Provides full document text on demand for AI, search, and TTS.
// Concatenates all chapters lazily — only called when these features are invoked,
// NOT during book open.
//
// Key decisions:
// - Actor-isolated for thread safety (concurrent getFullText calls are serialized).
// - Caches the full text after first successful concatenation.
// - Failed loads do NOT cache — subsequent calls can retry.
// - O(file_size) but only invoked on demand, never during book open.
//
// @coordinates-with: TXTChapter.swift, TXTChapterContentLoader.swift,
//   BookContentCache.swift

import Foundation

/// Provides full text on demand for AI, search, and TTS.
/// Concatenates all chapters lazily — only called when these features are invoked,
/// NOT during book open.
actor TXTLazyTextProvider {
    private let contentLoader: TXTChapterContentLoader
    private let chapters: [TXTChapter]
    private var cachedFullText: String?

    init(contentLoader: TXTChapterContentLoader, chapters: [TXTChapter]) {
        self.contentLoader = contentLoader
        self.chapters = chapters
    }

    /// Returns the full document text by concatenating all chapters.
    /// Cached after first successful call. O(file_size) but only invoked on demand.
    func getFullText() async throws -> String {
        if let cached = cachedFullText { return cached }

        var parts: [String] = []
        parts.reserveCapacity(chapters.count)
        for chapter in chapters {
            let text = try await contentLoader.loadChapter(chapter)
            parts.append(text)
        }
        let full = parts.joined()
        cachedFullText = full
        return full
    }

    /// Invalidates the cached full text (e.g., if chapters change).
    func invalidateCache() {
        cachedFullText = nil
    }
}
