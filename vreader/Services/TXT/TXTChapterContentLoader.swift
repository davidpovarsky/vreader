// Purpose: Loads chapter content from raw file data by byte range.
// Uses a 3-chapter LRU cache (prev/cur/next Legado pattern) to minimize
// redundant decoding while keeping memory bounded.
//
// Key decisions:
// - Actor-isolated for thread safety (concurrent chapter loads are safe).
// - fileData is expected to be memory-mapped (.mappedIfSafe) for large files.
// - Cache evicts the entry furthest from the current chapter index.
// - Empty byte ranges (startByte >= endByte or startByte >= data.count) return "".
//
// @coordinates-with: TXTChapter (WI-1), TXTService.swift, TXTReaderViewModel.swift

import Foundation

/// Loads chapter content from raw file data by byte range.
/// Uses a 3-chapter LRU cache (prev/cur/next Legado pattern).
actor TXTChapterContentLoader {
    private let fileData: Data  // memory-mapped
    private let encoding: String.Encoding
    private var cache: [Int: String] = [:]  // chapterIndex -> decoded text
    static let maxCacheSize = 3

    init(fileData: Data, encoding: String.Encoding) {
        self.fileData = fileData
        self.encoding = encoding
    }

    /// Loads a chapter's text by decoding its byte range.
    /// Returns cached result if available.
    func loadChapter(_ chapter: TXTChapter) throws -> String {
        if let cached = cache[chapter.index] { return cached }

        let start = Int(chapter.startByte)
        let end = min(Int(chapter.endByte), fileData.count)
        guard start < end else { return "" }

        let slice = fileData[start..<end]
        guard let text = String(data: Data(slice), encoding: encoding) else {
            throw TXTChapterLoadError.decodeFailed(chapterIndex: chapter.index)
        }

        // Evict if cache full
        if cache.count >= Self.maxCacheSize {
            // Remove the entry furthest from chapter.index
            let sorted = cache.keys.sorted {
                abs($0 - chapter.index) > abs($1 - chapter.index)
            }
            if let evict = sorted.first { cache.removeValue(forKey: evict) }
        }

        cache[chapter.index] = text
        return text
    }

    /// Preloads adjacent chapters (prev + next) in background.
    func preloadAdjacent(currentIndex: Int, chapters: [TXTChapter]) {
        let indices = [currentIndex - 1, currentIndex + 1]
        for i in indices {
            guard i >= 0, i < chapters.count else { continue }
            _ = try? loadChapter(chapters[i])
        }
    }

    /// Evicts all entries except the given indices.
    func evictExcept(indices: Set<Int>) {
        for key in cache.keys where !indices.contains(key) {
            cache.removeValue(forKey: key)
        }
    }

    /// Current cache size.
    var cacheCount: Int { cache.count }
}

/// Errors from TXTChapterContentLoader.
enum TXTChapterLoadError: Error, Sendable {
    case decodeFailed(chapterIndex: Int)
}
