// Purpose: Tests for UpdateChecker — detects new chapters by comparing
// remote TOC chapter count against a stored count.
//
// @coordinates-with: UpdateChecker.swift, BookSourcePipeline.swift,
//   PipelineTypes.swift, BookSourceSnapshot

import Testing
import Foundation
@testable import vreader

/// Actor-isolated call tracker for verifying whether a fetcher was called.
private actor FetchCallTracker {
    private(set) var wasCalled = false
    func recordCall() { wasCalled = true }
}

@Suite("UpdateChecker")
struct UpdateCheckerTests {

    // MARK: - Fixture HTML

    /// TOC HTML with 5 chapters (uses <li> pattern matching existing pipeline tests).
    private let tocHTML5 = """
    <html><body><div id="chapter-list"><ul class="chapters"><li><a href="/ch/1">Chapter 1</a></li><li><a href="/ch/2">Chapter 2</a></li><li><a href="/ch/3">Chapter 3</a></li><li><a href="/ch/4">Chapter 4</a></li><li><a href="/ch/5">Chapter 5</a></li></ul></div></body></html>
    """

    /// TOC HTML with 3 chapters (fewer than stored).
    private let tocHTML3 = """
    <html><body><div id="chapter-list"><ul class="chapters"><li><a href="/ch/1">Chapter 1</a></li><li><a href="/ch/2">Chapter 2</a></li><li><a href="/ch/3">Chapter 3</a></li></ul></div></body></html>
    """

    /// TOC HTML with 0 chapters (empty list).
    private let tocHTMLEmpty = """
    <html><body><div id="chapter-list"><ul class="chapters"></ul></div></body></html>
    """

    /// A source snapshot with TOC rules that extract chapters from fixture HTML.
    /// Uses `li` for chapterList matching the pattern in BookSourcePipelineTests.
    private func makeSource(
        sourceURL: String = "https://example.com",
        enabled: Bool = true,
        tocUrl: String = "https://example.com/book/1/toc"
    ) -> BookSourceSnapshot {
        BookSourceSnapshot(
            sourceURL: sourceURL,
            sourceName: "Test Source",
            ruleToc: BSTocRule(
                chapterList: "li",
                chapterName: "a",
                chapterUrl: "a@href"
            )
        )
    }

    /// A fetcher that returns the given HTML for any request.
    private func makeFetcher(_ html: String) -> HTMLFetchProvider {
        { _, _ in html }
    }

    /// A fetcher that throws the given error.
    private func makeErrorFetcher(_ error: Error) -> HTMLFetchProvider {
        { _, _ in throw error }
    }

    // MARK: - Test: New Chapters Detected

    @Test("New chapters are detected when remote count exceeds last known")
    func updateCheck_newChapters_detected() async throws {
        let checker = UpdateChecker()
        let source = makeSource()
        let fetcher = makeFetcher(tocHTML5)

        // Last known: 3 chapters; Remote: 5 chapters → 2 new
        let result = try await checker.checkForUpdates(
            source: source,
            bookURL: "https://example.com/book/1",
            tocURL: "https://example.com/book/1/toc",
            lastKnownChapterCount: 3,
            fetcher: fetcher
        )

        #expect(result != nil)
        #expect(result?.newChapterCount == 2)
        #expect(result?.sourceURL == "https://example.com")
        #expect(result?.bookURL == "https://example.com/book/1")
    }

    // MARK: - Test: No New Chapters

    @Test("No notification when chapter count is unchanged")
    func updateCheck_noNewChapters_noNotification() async throws {
        let checker = UpdateChecker()
        let source = makeSource()
        let fetcher = makeFetcher(tocHTML5)

        // Last known: 5, Remote: 5 → no update
        let result = try await checker.checkForUpdates(
            source: source,
            bookURL: "https://example.com/book/1",
            tocURL: "https://example.com/book/1/toc",
            lastKnownChapterCount: 5,
            fetcher: fetcher
        )

        #expect(result == nil)
    }

    // MARK: - Test: Network Error → Graceful Degradation

    @Test("Network error returns nil instead of crashing")
    func updateCheck_networkError_gracefulDegradation() async throws {
        let checker = UpdateChecker()
        let source = makeSource()
        let fetcher = makeErrorFetcher(
            HTTPClientError.networkError("Connection refused")
        )

        let result = try await checker.checkForUpdates(
            source: source,
            bookURL: "https://example.com/book/1",
            tocURL: "https://example.com/book/1/toc",
            lastKnownChapterCount: 3,
            fetcher: fetcher
        )

        // Should degrade gracefully, not throw
        #expect(result == nil)
    }

    // MARK: - Test: Disabled Source Skipped

    @Test("Disabled source is skipped — returns nil immediately")
    func updateCheck_disabledSource_skipped() async throws {
        let checker = UpdateChecker()
        let source = makeSource(enabled: false)

        let tracker = FetchCallTracker()
        let fetcher: HTMLFetchProvider = { [tracker] _, _ in
            await tracker.recordCall()
            return self.tocHTML5
        }

        let result = try await checker.checkForUpdates(
            source: source,
            bookURL: "https://example.com/book/1",
            tocURL: "https://example.com/book/1/toc",
            lastKnownChapterCount: 3,
            fetcher: fetcher,
            sourceEnabled: false
        )

        #expect(result == nil)
        let wasCalled = await tracker.wasCalled
        #expect(!wasCalled, "Fetcher should not be called for disabled source")
    }

    // MARK: - Test: Rate Limiting

    @Test("Rate-limited check respects minimum interval")
    func updateCheck_rateLimited() async throws {
        let checker = UpdateChecker(minimumCheckInterval: 3600) // 1 hour

        let source = makeSource()
        let fetcher = makeFetcher(tocHTML5)

        // First check should work
        let result1 = try await checker.checkForUpdates(
            source: source,
            bookURL: "https://example.com/book/1",
            tocURL: "https://example.com/book/1/toc",
            lastKnownChapterCount: 3,
            fetcher: fetcher
        )
        #expect(result1 != nil)

        // Second check immediately after should be rate-limited → nil
        let result2 = try await checker.checkForUpdates(
            source: source,
            bookURL: "https://example.com/book/1",
            tocURL: "https://example.com/book/1/toc",
            lastKnownChapterCount: 3,
            fetcher: fetcher
        )
        #expect(result2 == nil)
    }

    // MARK: - Edge Case: Chapter Count Decreased

    @Test("Chapter count decreased is handled gracefully (returns nil)")
    func updateCheck_chapterCountDecreased_noFalsePositive() async throws {
        let checker = UpdateChecker()
        let source = makeSource()
        let fetcher = makeFetcher(tocHTML3)

        // Last known: 5, Remote: 3 → decrease, not new chapters
        let result = try await checker.checkForUpdates(
            source: source,
            bookURL: "https://example.com/book/1",
            tocURL: "https://example.com/book/1/toc",
            lastKnownChapterCount: 5,
            fetcher: fetcher
        )

        #expect(result == nil)
    }

    // MARK: - Edge Case: Zero Last Known (first check)

    @Test("First check with zero last known detects all as new")
    func updateCheck_zeroLastKnown_allNew() async throws {
        let checker = UpdateChecker()
        let source = makeSource()
        let fetcher = makeFetcher(tocHTML5)

        let result = try await checker.checkForUpdates(
            source: source,
            bookURL: "https://example.com/book/1",
            tocURL: "https://example.com/book/1/toc",
            lastKnownChapterCount: 0,
            fetcher: fetcher
        )

        #expect(result != nil)
        #expect(result?.newChapterCount == 5)
    }

    // MARK: - Edge Case: Empty TOC

    @Test("Empty TOC returns nil, not crash")
    func updateCheck_emptyTOC_returnsNil() async throws {
        let checker = UpdateChecker()
        let source = makeSource()
        let fetcher = makeFetcher(tocHTMLEmpty)

        let result = try await checker.checkForUpdates(
            source: source,
            bookURL: "https://example.com/book/1",
            tocURL: "https://example.com/book/1/toc",
            lastKnownChapterCount: 3,
            fetcher: fetcher
        )

        #expect(result == nil)
    }

    // MARK: - Edge Case: Empty TOC URL

    @Test("Empty TOC URL returns nil")
    func updateCheck_emptyTocURL_returnsNil() async throws {
        let checker = UpdateChecker()
        let source = makeSource()
        let fetcher = makeFetcher(tocHTML5)

        let result = try await checker.checkForUpdates(
            source: source,
            bookURL: "https://example.com/book/1",
            tocURL: "",
            lastKnownChapterCount: 3,
            fetcher: fetcher
        )

        #expect(result == nil)
    }
}
