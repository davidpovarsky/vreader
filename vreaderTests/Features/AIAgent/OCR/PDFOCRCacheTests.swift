// Purpose: Unit tests for PDFOCRCache disk persistence and versioning.
// Tests cache hits, cache misses, book removal, and pipeline version invalidation.

import Testing
import Foundation
@testable import vreader

@Suite("PDFOCRCacheTests")
struct PDFOCRCacheTests {

    @Test func cacheStoreAndRetrieveRoundTrip() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = PDFOCRCache(storageDirectory: tempDir, currentPipelineVersion: 1)
        let result = PDFOCRResult(
            bookFingerprintKey: "book-1",
            pageIndex: 3,
            text: "Cached OCR output text",
            source: .visionOCR,
            confidence: 0.88,
            language: "en-US"
        )

        await cache.set(result, for: "book-1", pageIndex: 3)
        let retrieved = await cache.get(bookFingerprintKey: "book-1", pageIndex: 3)

        #expect(retrieved != nil)
        #expect(retrieved?.text == "Cached OCR output text")
        #expect(retrieved?.pageIndex == 3)
        #expect(retrieved?.source == .visionOCR)
    }

    @Test func pipelineVersionMismatchInvalidatesCachedEntry() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cacheV1 = PDFOCRCache(storageDirectory: tempDir, currentPipelineVersion: 1)
        let result = PDFOCRResult(
            bookFingerprintKey: "book-1",
            pageIndex: 0,
            text: "Version 1 text",
            source: .visionOCR
        )
        await cacheV1.set(result, for: "book-1", pageIndex: 0)

        // Reading with cache configured for version 2
        let cacheV2 = PDFOCRCache(storageDirectory: tempDir, currentPipelineVersion: 2)
        let retrieved = await cacheV2.get(bookFingerprintKey: "book-1", pageIndex: 0)

        #expect(retrieved == nil)
    }

    @Test func clearForBookRemovesOnlyTargetBook() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = PDFOCRCache(storageDirectory: tempDir, currentPipelineVersion: 1)
        let resA = PDFOCRResult(bookFingerprintKey: "book-A", pageIndex: 1, text: "A", source: .visionOCR)
        let resB = PDFOCRResult(bookFingerprintKey: "book-B", pageIndex: 1, text: "B", source: .visionOCR)

        await cache.set(resA, for: "book-A", pageIndex: 1)
        await cache.set(resB, for: "book-B", pageIndex: 1)

        await cache.clear(for: "book-A")

        #expect(await cache.get(bookFingerprintKey: "book-A", pageIndex: 1) == nil)
        #expect(await cache.get(bookFingerprintKey: "book-B", pageIndex: 1) != nil)
    }
}
