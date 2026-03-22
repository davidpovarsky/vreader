// Purpose: Tests for TXTLazyTextProvider — lazy full-text concatenation
// for AI, search, and TTS features.

import Testing
import Foundation
@testable import vreader

// MARK: - Mock Content Loader

/// Mock content loader that returns predetermined text for each chapter.
private final class MockChapterContentLoader: TXTChapterContentLoader, @unchecked Sendable {
    private var chapterTexts: [String: String] = [:]
    private var loadCount = 0
    private let lock = NSLock()
    private var shouldThrow = false

    func setTexts(_ texts: [(TXTChapter, String)]) {
        for (chapter, text) in texts {
            chapterTexts[chapter.title] = text
        }
    }

    func setShouldThrow(_ value: Bool) {
        lock.lock()
        shouldThrow = value
        lock.unlock()
    }

    func getLoadCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return loadCount
    }

    func loadChapter(_ chapter: TXTChapter) async throws -> String {
        lock.lock()
        let willThrow = shouldThrow
        loadCount += 1
        lock.unlock()

        if willThrow {
            throw MockLoaderError.loadFailed
        }
        return chapterTexts[chapter.title] ?? ""
    }
}

private enum MockLoaderError: Error {
    case loadFailed
}

// MARK: - Tests

@Suite("TXTLazyTextProvider")
struct TXTLazyTextProviderTests {

    // MARK: - Fixtures

    private static let chapters = [
        TXTChapter(title: "Chapter 1", globalStartUTF16: 0, textLengthUTF16: 13),
        TXTChapter(title: "Chapter 2", globalStartUTF16: 13, textLengthUTF16: 13),
        TXTChapter(title: "Chapter 3", globalStartUTF16: 26, textLengthUTF16: 13),
    ]

    private static func makeLoader() -> MockChapterContentLoader {
        let loader = MockChapterContentLoader()
        loader.setTexts([
            (chapters[0], "Hello, World!"),
            (chapters[1], "Second chunk."),
            (chapters[2], "Third chapter"),
        ])
        return loader
    }

    // MARK: - getFullText

    @Test("getFullText concatenates all chapters")
    func testGetFullTextConcatenatesAllChapters() async throws {
        let loader = Self.makeLoader()
        let provider = TXTLazyTextProvider(
            contentLoader: loader,
            chapters: Self.chapters
        )

        let fullText = try await provider.getFullText()
        #expect(fullText == "Hello, World!Second chunk.Third chapter")
    }

    @Test("getFullText caches result — only loads once")
    func testGetFullTextCachesResult() async throws {
        let loader = Self.makeLoader()
        let provider = TXTLazyTextProvider(
            contentLoader: loader,
            chapters: Self.chapters
        )

        let first = try await provider.getFullText()
        let second = try await provider.getFullText()

        #expect(first == second)
        // Should have loaded chapters only once (3 chapters = 3 loads)
        #expect(loader.getLoadCount() == 3)
    }

    @Test("invalidateCache forces reload on next getFullText")
    func testInvalidateCacheForcesReload() async throws {
        let loader = Self.makeLoader()
        let provider = TXTLazyTextProvider(
            contentLoader: loader,
            chapters: Self.chapters
        )

        _ = try await provider.getFullText()
        #expect(loader.getLoadCount() == 3)

        await provider.invalidateCache()

        _ = try await provider.getFullText()
        // Should have loaded again (3 + 3 = 6 total loads)
        #expect(loader.getLoadCount() == 6)
    }

    @Test("empty chapters returns empty string")
    func testEmptyChaptersReturnsEmptyString() async throws {
        let loader = MockChapterContentLoader()
        let provider = TXTLazyTextProvider(
            contentLoader: loader,
            chapters: []
        )

        let fullText = try await provider.getFullText()
        #expect(fullText == "")
        #expect(loader.getLoadCount() == 0)
    }

    @Test("single chapter returns its text without joining artifacts")
    func testSingleChapter() async throws {
        let chapter = TXTChapter(title: "Only", globalStartUTF16: 0, textLengthUTF16: 5)
        let loader = MockChapterContentLoader()
        loader.setTexts([(chapter, "Hello")])

        let provider = TXTLazyTextProvider(
            contentLoader: loader,
            chapters: [chapter]
        )

        let fullText = try await provider.getFullText()
        #expect(fullText == "Hello")
    }

    @Test("content loader throws — propagates error")
    func testContentLoaderThrowsPropagatesError() async {
        let loader = MockChapterContentLoader()
        loader.setShouldThrow(true)

        let provider = TXTLazyTextProvider(
            contentLoader: loader,
            chapters: Self.chapters
        )

        do {
            _ = try await provider.getFullText()
            Issue.record("Expected getFullText to throw")
        } catch {
            // Error should propagate
            #expect(error is MockLoaderError)
        }
    }

    @Test("error does not cache — subsequent call can succeed")
    func testErrorDoesNotCache() async throws {
        let loader = Self.makeLoader()
        loader.setShouldThrow(true)

        let provider = TXTLazyTextProvider(
            contentLoader: loader,
            chapters: Self.chapters
        )

        // First call should fail
        do {
            _ = try await provider.getFullText()
            Issue.record("Expected first call to throw")
        } catch {
            // expected
        }

        // Fix the loader
        loader.setShouldThrow(false)

        // Second call should succeed
        let text = try await provider.getFullText()
        #expect(text == "Hello, World!Second chunk.Third chapter")
    }

    @Test("chapters with empty text content")
    func testChaptersWithEmptyContent() async throws {
        let chapters = [
            TXTChapter(title: "Empty1", globalStartUTF16: 0, textLengthUTF16: 0),
            TXTChapter(title: "HasText", globalStartUTF16: 0, textLengthUTF16: 5),
            TXTChapter(title: "Empty2", globalStartUTF16: 5, textLengthUTF16: 0),
        ]
        let loader = MockChapterContentLoader()
        loader.setTexts([
            (chapters[0], ""),
            (chapters[1], "Hello"),
            (chapters[2], ""),
        ])

        let provider = TXTLazyTextProvider(
            contentLoader: loader,
            chapters: chapters
        )

        let fullText = try await provider.getFullText()
        #expect(fullText == "Hello")
    }
}
