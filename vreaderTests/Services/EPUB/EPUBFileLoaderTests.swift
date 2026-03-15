// Purpose: Tests for EPUBFileLoader — verifies parse + position restore logic
// extracted from EPUBReaderViewModel in WI-008b.
//
// @coordinates-with: EPUBFileLoader.swift, EPUBParserProtocol.swift, MockEPUBParser.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let testFP = DocumentFingerprint(
    contentSHA256: "epub_loader_test_sha256_000000000000000000000000000000000000",
    fileByteCount: 50000,
    format: .epub
)

private let testSpine = [
    EPUBSpineItem(id: "ch1", href: "chapter1.xhtml", title: "Chapter 1", index: 0),
    EPUBSpineItem(id: "ch2", href: "chapter2.xhtml", title: "Chapter 2", index: 1),
    EPUBSpineItem(id: "ch3", href: "chapter3.xhtml", title: "Chapter 3", index: 2),
]

private let testMeta = EPUBMetadata(
    title: "Loader Test",
    author: "Author",
    language: "en",
    readingDirection: .ltr,
    layout: .reflowable,
    spineItems: testSpine
)

private let testURL = URL(fileURLWithPath: "/tmp/loader-test.epub")

// MARK: - Tests

@Suite("EPUBFileLoader")
struct EPUBFileLoaderTests {

    @Test("load returns metadata from parser")
    func loadReturnsMetadata() async throws {
        let parser = MockEPUBParser()
        await parser.setMetadata(testMeta)
        let store = MockPositionStore()

        let result = try await EPUBFileLoader.load(
            url: testURL,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.metadata.title == "Loader Test")
        #expect(result.metadata.spineCount == 3)
        let openCount = await parser.openCallCount
        #expect(openCount == 1)
    }

    @Test("load restores saved position from store")
    func loadRestoresSavedPosition() async throws {
        let parser = MockEPUBParser()
        await parser.setMetadata(testMeta)
        let store = MockPositionStore()

        guard let savedLocator = LocatorFactory.epub(
            fingerprint: testFP,
            href: "chapter2.xhtml",
            progression: 0.5,
            totalProgression: 0.4
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await store.seed(bookFingerprintKey: testFP.canonicalKey, locator: savedLocator)

        let result = try await EPUBFileLoader.load(
            url: testURL,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.initialPosition?.href == "chapter2.xhtml")
        #expect(result.initialPosition?.progression == 0.5)
    }

    @Test("load falls back to first spine when no saved position")
    func loadFallsBackToFirstSpine() async throws {
        let parser = MockEPUBParser()
        await parser.setMetadata(testMeta)
        let store = MockPositionStore()

        let result = try await EPUBFileLoader.load(
            url: testURL,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.initialPosition?.href == "chapter1.xhtml")
        #expect(result.initialPosition?.progression == 0)
    }

    @Test("load falls back to first spine when saved href not in spine")
    func loadFallsBackOnStalePosition() async throws {
        let parser = MockEPUBParser()
        await parser.setMetadata(testMeta)
        let store = MockPositionStore()

        guard let savedLocator = LocatorFactory.epub(
            fingerprint: testFP,
            href: "deleted_chapter.xhtml",
            progression: 0.8,
            totalProgression: 0.9
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await store.seed(bookFingerprintKey: testFP.canonicalKey, locator: savedLocator)

        let result = try await EPUBFileLoader.load(
            url: testURL,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.initialPosition?.href == "chapter1.xhtml")
        #expect(result.initialPosition?.progression == 0)
    }

    @Test("load falls back to first spine on position load error")
    func loadFallsBackOnStoreError() async throws {
        let parser = MockEPUBParser()
        await parser.setMetadata(testMeta)
        let store = MockPositionStore()
        await store.setLoadError(NSError(domain: "test", code: 1))

        let result = try await EPUBFileLoader.load(
            url: testURL,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.initialPosition?.href == "chapter1.xhtml")
    }

    @Test("load throws on parser error preserving original type")
    func loadThrowsParserError() async {
        let parser = MockEPUBParser()
        await parser.setMetadata(testMeta)
        await parser.setOpenError(.fileNotFound("/tmp/bad.epub"))
        let store = MockPositionStore()

        do {
            _ = try await EPUBFileLoader.load(
                url: testURL,
                parser: parser,
                positionStore: store,
                bookFingerprintKey: testFP.canonicalKey
            )
            Issue.record("Expected load to throw")
        } catch let error as EPUBParserError {
            #expect(error == .fileNotFound("/tmp/bad.epub"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Bug #58: Intra-chapter position restore

    @Test("load restores intra-chapter progression from saved locator")
    func loadRestoresIntraChapterProgression() async throws {
        // Bug #58: saved progression was only chapter-level (0.0), not intra-chapter.
        // The loader must restore the exact saved progression fraction.
        let parser = MockEPUBParser()
        await parser.setMetadata(testMeta)
        let store = MockPositionStore()

        guard let savedLocator = LocatorFactory.epub(
            fingerprint: testFP,
            href: "chapter2.xhtml",
            progression: 0.73,
            totalProgression: 0.55
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await store.seed(bookFingerprintKey: testFP.canonicalKey, locator: savedLocator)

        let result = try await EPUBFileLoader.load(
            url: testURL,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.initialPosition?.href == "chapter2.xhtml")
        #expect(result.initialPosition?.progression == 0.73, "Progression within chapter must be preserved")
        #expect(result.initialPosition?.totalProgression == 0.55, "Total progression must be preserved")
    }

    @Test("load preserves zero progression when saved at chapter start")
    func loadPreservesZeroProgression() async throws {
        let parser = MockEPUBParser()
        await parser.setMetadata(testMeta)
        let store = MockPositionStore()

        guard let savedLocator = LocatorFactory.epub(
            fingerprint: testFP,
            href: "chapter3.xhtml",
            progression: 0.0,
            totalProgression: 0.67
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await store.seed(bookFingerprintKey: testFP.canonicalKey, locator: savedLocator)

        let result = try await EPUBFileLoader.load(
            url: testURL,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.initialPosition?.href == "chapter3.xhtml")
        #expect(result.initialPosition?.progression == 0.0)
        #expect(result.initialPosition?.totalProgression == 0.67)
    }

    @Test("load returns nil position for empty spine")
    func loadEmptySpine() async throws {
        let emptyMeta = EPUBMetadata(
            title: "Empty",
            author: nil,
            language: nil,
            readingDirection: .ltr,
            layout: .reflowable,
            spineItems: []
        )
        let parser = MockEPUBParser()
        await parser.setMetadata(emptyMeta)
        let store = MockPositionStore()

        let result = try await EPUBFileLoader.load(
            url: testURL,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.metadata.spineCount == 0)
        #expect(result.initialPosition == nil)
    }
}
