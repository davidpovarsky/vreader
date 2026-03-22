// Purpose: Tests for ChapterCache — disk-based LRU cache for offline chapter reading.
// Tests cover store/retrieve, persistence, eviction, corruption handling,
// and pipeline integration (cache hit skips network, cache miss fetches and caches).
//
// @coordinates-with: ChapterCache.swift, BookSourcePipeline.swift, PipelineTypes.swift

import Testing
import Foundation
@testable import vreader

@Suite("ChapterCache")
struct ChapterCacheTests {

    // MARK: - Helpers

    /// Creates a temporary directory for cache testing.
    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChapterCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tmp, withIntermediateDirectories: true
        )
        return tmp
    }

    /// Removes a temporary directory after test.
    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Store and Retrieve

    @Test func cache_storeAndRetrieve_chapter() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let cache = ChapterCache(directory: dir, maxSizeBytes: 100_000_000)
        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1",
            content: "第一章 陨落的天才"
        )

        let result = await cache.get(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1"
        )
        #expect(result == "第一章 陨落的天才")
    }

    // MARK: - Cache Miss

    @Test func cache_miss_returnsNil() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let cache = ChapterCache(directory: dir, maxSizeBytes: 100_000_000)
        let result = await cache.get(
            sourceURL: "https://example.com",
            chapterURL: "/ch/999"
        )
        #expect(result == nil)
    }

    // MARK: - Persists Across Instances

    @Test func cache_persistsAcrossInstances() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Write with first instance
        let cache1 = ChapterCache(directory: dir, maxSizeBytes: 100_000_000)
        await cache1.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1",
            content: "Persistent content 持久化内容"
        )

        // Read with second instance (same directory)
        let cache2 = ChapterCache(directory: dir, maxSizeBytes: 100_000_000)
        let result = await cache2.get(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1"
        )
        #expect(result == "Persistent content 持久化内容")
    }

    // MARK: - Book Deletion Clears Cached Chapters

    @Test func cache_bookDeletion_clearsCachedChapters() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let cache = ChapterCache(directory: dir, maxSizeBytes: 100_000_000)

        // Cache chapters for two sources
        await cache.set(
            sourceURL: "https://source-a.com",
            chapterURL: "/ch/1",
            content: "Source A Chapter 1"
        )
        await cache.set(
            sourceURL: "https://source-b.com",
            chapterURL: "/ch/1",
            content: "Source B Chapter 1"
        )

        // Clear source A only
        await cache.clear(sourceURL: "https://source-a.com")

        let resultA = await cache.get(
            sourceURL: "https://source-a.com",
            chapterURL: "/ch/1"
        )
        let resultB = await cache.get(
            sourceURL: "https://source-b.com",
            chapterURL: "/ch/1"
        )
        #expect(resultA == nil)
        #expect(resultB == "Source B Chapter 1")
    }

    // MARK: - Corrupted File Returns Nil and Cleans

    @Test func cache_corruptedFile_returnsNilAndCleans() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let cache = ChapterCache(directory: dir, maxSizeBytes: 100_000_000)

        // Store a valid chapter first to learn the file path
        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1",
            content: "Valid content"
        )

        // Corrupt the file on disk by writing invalid data
        let sourceHash = ChapterCache.hash(for: "https://example.com")
        let chapterHash = ChapterCache.hash(for: "/ch/1")
        let filePath = dir
            .appendingPathComponent(sourceHash)
            .appendingPathComponent(chapterHash + ".txt")

        // Write non-UTF8 bytes
        let corruptData = Data([0xFF, 0xFE, 0x00, 0x80])
        try corruptData.write(to: filePath)

        let result = await cache.get(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1"
        )
        #expect(result == nil)

        // Verify the corrupted file was cleaned up
        #expect(!FileManager.default.fileExists(atPath: filePath.path))
    }

    // MARK: - Pipeline: Cache Hit Skips Network

    @Test func pipeline_hitCache_skipsNetwork() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let cache = ChapterCache(directory: dir, maxSizeBytes: 100_000_000)

        // Pre-populate cache
        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "https://example.com/ch/1",
            content: "Cached chapter content 缓存内容"
        )

        let networkTracker = NetworkCallTracker()
        let fetchHTML: HTMLFetchProvider = { @Sendable _, _ in
            await networkTracker.markCalled()
            return "<html><body><div class='content'><p>Network content</p></div></body></html>"
        }

        let pipeline = BookSourcePipeline(
            fetchHTML: fetchHTML,
            chapterCache: cache
        )

        let source = BookSourceSnapshot(
            sourceURL: "https://example.com",
            sourceName: "Test",
            ruleContent: BSContentRule(content: ".content p")
        )

        let text = try await pipeline.chapterContent(
            source: source,
            chapterUrl: "https://example.com/ch/1"
        )

        #expect(text == "Cached chapter content 缓存内容")
        let wasCalled = await networkTracker.wasCalled
        #expect(!wasCalled)
    }

    // MARK: - Pipeline: Cache Miss Fetches and Caches

    @Test func pipeline_cacheMiss_fetchesAndCaches() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let cache = ChapterCache(directory: dir, maxSizeBytes: 100_000_000)

        let contentHTML = """
        <html><body>
          <div class="content">
            <p>从网络获取的章节内容</p>
          </div>
        </body></html>
        """

        let fetchHTML: HTMLFetchProvider = { @Sendable url, _ in
            return contentHTML
        }

        let pipeline = BookSourcePipeline(
            fetchHTML: fetchHTML,
            chapterCache: cache
        )

        let source = BookSourceSnapshot(
            sourceURL: "https://example.com",
            sourceName: "Test",
            ruleContent: BSContentRule(content: ".content p")
        )

        let text = try await pipeline.chapterContent(
            source: source,
            chapterUrl: "https://example.com/ch/1"
        )

        #expect(text.contains("从网络获取的章节内容"))

        // Verify it was cached
        let cached = await cache.get(
            sourceURL: "https://example.com",
            chapterURL: "https://example.com/ch/1"
        )
        #expect(cached == text)
    }

    // MARK: - Max Size Evicts LRU

    @Test func cache_maxSize_evictsLRU() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Use a tiny max size to force eviction
        // Each chapter is ~20 bytes, max = 50 bytes → only ~2 chapters fit
        let cache = ChapterCache(directory: dir, maxSizeBytes: 50)

        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1",
            content: "Chapter 1 content!!"
        )
        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/2",
            content: "Chapter 2 content!!"
        )
        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/3",
            content: "Chapter 3 content!!"
        )

        // ch/1 should have been evicted (LRU — oldest entry)
        let result1 = await cache.get(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1"
        )
        #expect(result1 == nil)

        // ch/3 should still be present (most recent)
        let result3 = await cache.get(
            sourceURL: "https://example.com",
            chapterURL: "/ch/3"
        )
        #expect(result3 == "Chapter 3 content!!")
    }

    // MARK: - Clear All

    @Test func cache_clearAll_removesEverything() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let cache = ChapterCache(directory: dir, maxSizeBytes: 100_000_000)

        await cache.set(
            sourceURL: "https://source-a.com",
            chapterURL: "/ch/1",
            content: "A"
        )
        await cache.set(
            sourceURL: "https://source-b.com",
            chapterURL: "/ch/1",
            content: "B"
        )

        await cache.clearAll()

        let a = await cache.get(
            sourceURL: "https://source-a.com", chapterURL: "/ch/1"
        )
        let b = await cache.get(
            sourceURL: "https://source-b.com", chapterURL: "/ch/1"
        )
        #expect(a == nil)
        #expect(b == nil)

        let size = await cache.totalSizeBytes
        #expect(size == 0)
    }

    // MARK: - Empty Content Not Cached

    @Test func cache_emptyContent_notCached() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let cache = ChapterCache(directory: dir, maxSizeBytes: 100_000_000)
        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1",
            content: ""
        )

        let result = await cache.get(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1"
        )
        #expect(result == nil)
    }

    // MARK: - Total Size Tracking

    @Test func cache_totalSizeBytes_tracksCorrectly() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let cache = ChapterCache(directory: dir, maxSizeBytes: 100_000_000)

        #expect(await cache.totalSizeBytes == 0)

        let content = "Hello, World! 你好世界"
        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1",
            content: content
        )

        let expectedSize = Int64(content.utf8.count)
        #expect(await cache.totalSizeBytes == expectedSize)
    }

    // MARK: - Overwrite Updates Content

    @Test func cache_overwrite_updatesContent() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let cache = ChapterCache(directory: dir, maxSizeBytes: 100_000_000)

        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1",
            content: "Version 1"
        )
        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1",
            content: "Version 2"
        )

        let result = await cache.get(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1"
        )
        #expect(result == "Version 2")
    }

    // MARK: - LRU: Access Refreshes Entry

    @Test func cache_lru_accessRefreshesEntry() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Max ~40 bytes, each entry ~20 bytes → 2 entries fit
        let cache = ChapterCache(directory: dir, maxSizeBytes: 45)

        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1",
            content: "Chapter 1 content!!"
        )
        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/2",
            content: "Chapter 2 content!!"
        )

        // Access ch/1 to refresh its LRU position
        _ = await cache.get(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1"
        )

        // Add ch/3 — should evict ch/2 (now oldest), not ch/1
        await cache.set(
            sourceURL: "https://example.com",
            chapterURL: "/ch/3",
            content: "Chapter 3 content!!"
        )

        let result1 = await cache.get(
            sourceURL: "https://example.com",
            chapterURL: "/ch/1"
        )
        let result2 = await cache.get(
            sourceURL: "https://example.com",
            chapterURL: "/ch/2"
        )

        // ch/1 was refreshed, so ch/2 should be the evicted one
        #expect(result1 == "Chapter 1 content!!")
        #expect(result2 == nil)
    }
}

// MARK: - Test Helpers

/// Actor for tracking network calls safely across concurrency boundaries.
private actor NetworkCallTracker {
    var wasCalled = false
    func markCalled() { wasCalled = true }
}
