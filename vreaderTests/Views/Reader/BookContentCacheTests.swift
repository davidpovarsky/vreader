// Purpose: Tests for BookContentCache — shared content loading for reader.
// Ensures single-load semantics and correct cache behavior.
//
// @coordinates-with: BookContentCache.swift, ReaderContainerView.swift

import Testing
import Foundation
@testable import vreader

@Suite("BookContentCache")
struct BookContentCacheTests {

    @Test @MainActor func getText_returnsNilForMissingFile() async {
        let cache = BookContentCache()
        let bogusURL = URL(fileURLWithPath: "/nonexistent/book.txt")

        let text = await cache.getText(for: bogusURL, format: "txt")

        #expect(text == nil)
    }

    @Test @MainActor func getText_cachesResultAfterFirstLoad() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test-cache-\(UUID()).txt")
        try "Hello World".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let cache = BookContentCache()

        let text1 = await cache.getText(for: tempFile, format: "txt")
        #expect(text1 == "Hello World")

        // Modify file — cache should return original
        try "Modified".write(to: tempFile, atomically: true, encoding: .utf8)
        let text2 = await cache.getText(for: tempFile, format: "txt")
        #expect(text2 == "Hello World", "Should return cached result, not re-read")
    }

    @Test @MainActor func getText_differentFilesAreCachedSeparately() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file1 = tempDir.appendingPathComponent("cache-test-1-\(UUID()).txt")
        let file2 = tempDir.appendingPathComponent("cache-test-2-\(UUID()).txt")
        try "Content A".write(to: file1, atomically: true, encoding: .utf8)
        try "Content B".write(to: file2, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: file1)
            try? FileManager.default.removeItem(at: file2)
        }

        let cache = BookContentCache()

        let text1 = await cache.getText(for: file1, format: "txt")
        let text2 = await cache.getText(for: file2, format: "txt")
        #expect(text1 == "Content A")
        #expect(text2 == "Content B")
    }

    @Test @MainActor func getText_emptyFileReturnsNil() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("empty-\(UUID()).txt")
        try "".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let cache = BookContentCache()

        let text = await cache.getText(for: tempFile, format: "txt")
        #expect(text == nil, "Empty content should return nil")
    }

    @Test @MainActor func invalidate_clearsCache() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("invalidate-\(UUID()).txt")
        try "Original".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let cache = BookContentCache()

        _ = await cache.getText(for: tempFile, format: "txt")

        // Modify file and invalidate
        try "Updated".write(to: tempFile, atomically: true, encoding: .utf8)
        cache.invalidate(for: tempFile)

        let text = await cache.getText(for: tempFile, format: "txt")
        #expect(text == "Updated", "After invalidation, should re-read file")
    }

    @Test @MainActor func getText_mdFormatReturnsText() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test-\(UUID()).md")
        try "# Heading\n\nParagraph".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let cache = BookContentCache()
        let text = await cache.getText(for: tempFile, format: "md")
        #expect(text != nil, "MD files should be loadable")
    }
}
