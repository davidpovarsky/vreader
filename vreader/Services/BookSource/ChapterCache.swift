// Purpose: Disk-based LRU cache for chapter content, enabling offline reading.
// Stores chapter text as plain files: <directory>/<sourceHash>/<chapterHash>.txt
// Uses an in-memory LRU index with JSON manifest persistence per source.
//
// Key decisions:
// - Actor-isolated for thread safety during concurrent reads/writes.
// - Disk-based persistence survives app restarts.
// - LRU eviction when total size exceeds configurable max (default 500MB).
// - Empty content is never cached.
// - Corrupted files are cleaned up on read.
// - Static hash function exposed for test verification.
//
// @coordinates-with: BookSourcePipeline.swift, PipelineTypes.swift

import Foundation
import CryptoKit

/// Disk-based LRU cache for chapter content.
///
/// Files are stored at `<directory>/<sourceHash>/<chapterHash>.txt`.
/// An in-memory LRU index tracks access order for eviction.
/// The index is rebuilt from disk on first access (lazy initialization).
actor ChapterCache {

    /// Root directory for cache files.
    private let directory: URL

    /// Maximum total cache size in bytes before LRU eviction.
    private let maxSizeBytes: Int64

    /// In-memory LRU index: ordered list of cache entries (oldest first).
    private var lruEntries: [CacheEntry] = []

    /// Current total size of all cached files.
    private var currentSizeBytes: Int64 = 0

    /// Whether the index has been loaded from disk.
    private var indexLoaded = false

    // MARK: - Types

    /// Metadata for a single cached chapter.
    private struct CacheEntry: Equatable {
        let sourceHash: String
        let chapterHash: String
        let sizeBytes: Int64
        var lastAccess: Date

        /// Unique key combining source and chapter.
        var key: String { "\(sourceHash)/\(chapterHash)" }
    }

    // MARK: - Init

    /// Creates a chapter cache backed by the given directory.
    ///
    /// - Parameters:
    ///   - directory: Root directory for cache files.
    ///   - maxSizeBytes: Maximum cache size before eviction (default 500MB).
    init(directory: URL, maxSizeBytes: Int64 = 500 * 1024 * 1024) {
        self.directory = directory
        self.maxSizeBytes = maxSizeBytes
    }

    // MARK: - Public API

    /// Retrieves cached chapter content, or nil on miss/corruption.
    ///
    /// On cache hit, updates LRU access time.
    /// On corruption (non-UTF8 data), deletes the file and returns nil.
    func get(sourceURL: String, chapterURL: String) -> String? {
        ensureIndexLoaded()

        let sHash = Self.hash(for: sourceURL)
        let cHash = Self.hash(for: chapterURL)
        let key = "\(sHash)/\(cHash)"
        let filePath = directory
            .appendingPathComponent(sHash)
            .appendingPathComponent(cHash + ".txt")

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            // Remove stale index entry if any
            removeFromIndex(key: key)
            return nil
        }

        do {
            let data = try Data(contentsOf: filePath)
            guard let content = String(data: data, encoding: .utf8) else {
                // Corrupted: non-UTF8 data
                try? FileManager.default.removeItem(at: filePath)
                removeFromIndex(key: key)
                return nil
            }

            if content.isEmpty {
                try? FileManager.default.removeItem(at: filePath)
                removeFromIndex(key: key)
                return nil
            }

            // Update LRU access time
            touchEntry(key: key)

            return content
        } catch {
            // Read error — treat as corruption
            try? FileManager.default.removeItem(at: filePath)
            removeFromIndex(key: key)
            return nil
        }
    }

    /// Caches chapter content to disk. Empty content is silently ignored.
    ///
    /// After writing, triggers LRU eviction if total exceeds maxSizeBytes.
    func set(sourceURL: String, chapterURL: String, content: String) {
        guard !content.isEmpty else { return }

        ensureIndexLoaded()

        let sHash = Self.hash(for: sourceURL)
        let cHash = Self.hash(for: chapterURL)
        let key = "\(sHash)/\(cHash)"

        let sourceDir = directory.appendingPathComponent(sHash)
        let filePath = sourceDir.appendingPathComponent(cHash + ".txt")

        // Remove old entry size if overwriting
        let oldSize = removeFromIndex(key: key)
        currentSizeBytes -= oldSize

        do {
            try FileManager.default.createDirectory(
                at: sourceDir, withIntermediateDirectories: true
            )
            let data = Data(content.utf8)
            try data.write(to: filePath, options: .atomic)

            let size = Int64(data.count)
            lruEntries.append(CacheEntry(
                sourceHash: sHash,
                chapterHash: cHash,
                sizeBytes: size,
                lastAccess: Date()
            ))
            currentSizeBytes += size

            evictIfNeeded()
        } catch {
            // Write failed silently — cache is best-effort
        }
    }

    /// Removes all cached chapters for a given source.
    func clear(sourceURL: String) {
        ensureIndexLoaded()

        let sHash = Self.hash(for: sourceURL)
        let sourceDir = directory.appendingPathComponent(sHash)

        // Remove from index
        let removed = lruEntries.filter { $0.sourceHash == sHash }
        lruEntries.removeAll { $0.sourceHash == sHash }
        currentSizeBytes -= removed.reduce(0) { $0 + $1.sizeBytes }

        // Remove from disk
        try? FileManager.default.removeItem(at: sourceDir)
    }

    /// Removes all cached chapters for all sources.
    func clearAll() {
        lruEntries.removeAll()
        currentSizeBytes = 0
        indexLoaded = true

        // Remove all contents of the cache directory
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) {
            for item in contents {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    /// The current total size of all cached files in bytes.
    var totalSizeBytes: Int64 {
        ensureIndexLoaded()
        return currentSizeBytes
    }

    // MARK: - Hashing (exposed for test verification)

    /// Computes a SHA-256 hash string for a given input.
    /// Exposed as static for test verification of file paths.
    static func hash(for input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private Helpers

    /// Loads the LRU index from disk by scanning the cache directory.
    private func ensureIndexLoaded() {
        guard !indexLoaded else { return }
        indexLoaded = true
        rebuildIndex()
    }

    /// Scans the cache directory and rebuilds the in-memory LRU index.
    private func rebuildIndex() {
        lruEntries.removeAll()
        currentSizeBytes = 0

        let fm = FileManager.default
        guard let sourceDirs = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        for sourceDir in sourceDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: sourceDir.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            let sourceHash = sourceDir.lastPathComponent
            guard let files = try? fm.contentsOfDirectory(
                at: sourceDir, includingPropertiesForKeys: [
                    .fileSizeKey, .contentModificationDateKey
                ]
            ) else { continue }

            for file in files where file.pathExtension == "txt" {
                let chapterHash = file.deletingPathExtension().lastPathComponent
                let attrs = try? file.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                )
                let size = Int64(attrs?.fileSize ?? 0)
                let modDate = attrs?.contentModificationDate ?? Date.distantPast

                lruEntries.append(CacheEntry(
                    sourceHash: sourceHash,
                    chapterHash: chapterHash,
                    sizeBytes: size,
                    lastAccess: modDate
                ))
                currentSizeBytes += size
            }
        }

        // Sort by access time: oldest first
        lruEntries.sort { $0.lastAccess < $1.lastAccess }
    }

    /// Updates the access time for a cache entry (moves it to the end).
    private func touchEntry(key: String) {
        guard let idx = lruEntries.firstIndex(where: { $0.key == key }) else {
            return
        }
        var entry = lruEntries.remove(at: idx)
        entry.lastAccess = Date()
        lruEntries.append(entry)

        // Also touch the file modification date
        let filePath = directory
            .appendingPathComponent(entry.sourceHash)
            .appendingPathComponent(entry.chapterHash + ".txt")
        try? FileManager.default.setAttributes(
            [.modificationDate: entry.lastAccess],
            ofItemAtPath: filePath.path
        )
    }

    /// Removes an entry from the index and returns its size (0 if not found).
    @discardableResult
    private func removeFromIndex(key: String) -> Int64 {
        guard let idx = lruEntries.firstIndex(where: { $0.key == key }) else {
            return 0
        }
        let entry = lruEntries.remove(at: idx)
        return entry.sizeBytes
    }

    /// Evicts the oldest entries until totalSize is within maxSizeBytes.
    private func evictIfNeeded() {
        while currentSizeBytes > maxSizeBytes, !lruEntries.isEmpty {
            let oldest = lruEntries.removeFirst()
            currentSizeBytes -= oldest.sizeBytes

            let filePath = directory
                .appendingPathComponent(oldest.sourceHash)
                .appendingPathComponent(oldest.chapterHash + ".txt")
            try? FileManager.default.removeItem(at: filePath)

            // Clean up empty source directory
            let sourceDir = directory.appendingPathComponent(oldest.sourceHash)
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: sourceDir, includingPropertiesForKeys: nil
            ), contents.isEmpty {
                try? FileManager.default.removeItem(at: sourceDir)
            }
        }
    }
}
