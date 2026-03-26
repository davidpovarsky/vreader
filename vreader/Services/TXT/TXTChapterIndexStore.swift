// Purpose: Persists and loads TXTChapterIndex as JSON, keyed by file metadata
// (byte count + modification date) for cache invalidation. Stored at
// {cacheDir}/chapter-index.json.
//
// Key decisions:
// - JSON encoding with ISO 8601 dates for cross-platform safety.
// - Atomic writes via Data.write with .atomic option.
// - Load returns nil on any error (missing, corrupt, stale) — no throws.
// - CacheWrapper stores file metadata alongside the index for validation.
//
// @coordinates-with: TXTChapterTypes.swift

import Foundation

/// Persists/loads TXTChapterIndex as JSON. Keyed by file metadata for invalidation.
enum TXTChapterIndexStore {

    private static let fileName = "chapter-index.json"

    // MARK: - Cache Wrapper

    struct CacheWrapper: Codable {
        let fileByteCount: Int64
        let fileModTime: TimeInterval  // Date.timeIntervalSince1970
        let index: TXTChapterIndex
    }

    // MARK: - Public API

    /// Loads cached index if file metadata matches. Returns nil on miss/stale/corrupt.
    static func load(cacheDir: URL, fileByteCount: Int64, fileModDate: Date) -> TXTChapterIndex? {
        let filePath = cacheDir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: filePath) else { return nil }

        let decoder = JSONDecoder()
        guard let wrapper = try? decoder.decode(CacheWrapper.self, from: data) else { return nil }

        // Validate file metadata
        guard wrapper.fileByteCount == fileByteCount,
              wrapper.fileModTime == fileModDate.timeIntervalSince1970 else {
            return nil
        }

        return wrapper.index
    }

    /// Saves index with file metadata for future validation.
    static func save(
        _ index: TXTChapterIndex,
        cacheDir: URL,
        fileByteCount: Int64,
        fileModDate: Date
    ) throws {
        let wrapper = CacheWrapper(
            fileByteCount: fileByteCount,
            fileModTime: fileModDate.timeIntervalSince1970,
            index: index
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(wrapper)

        let filePath = cacheDir.appendingPathComponent(fileName)
        try data.write(to: filePath, options: .atomic)
    }

    /// Deletes the cached index file.
    static func invalidate(cacheDir: URL) {
        let filePath = cacheDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: filePath)
    }
}
