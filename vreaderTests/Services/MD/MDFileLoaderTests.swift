// Purpose: Tests for MDFileLoader — verifies file read + parse + position restore
// logic extracted from MDReaderViewModel in WI-008c.
//
// @coordinates-with: MDFileLoader.swift, MDParserProtocol.swift, MockMDParser.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let testFP = DocumentFingerprint(
    contentSHA256: "md_loader_test_sha256_00000000000000000000000000000000000000",
    fileByteCount: 500,
    format: .md
)

private let testRenderedText = "Title\nHello world. This is rendered markdown content.\n"
private let testMDSource = "# Title\n\nHello world. This is **rendered** markdown content.\n"

private func makeDocumentInfo(
    renderedText: String = testRenderedText
) -> MDDocumentInfo {
    MDDocumentInfo(
        renderedText: renderedText,
        renderedAttributedString: NSAttributedString(string: renderedText),
        headings: [MDHeading(level: 1, text: "Title", charOffsetUTF16: 0)],
        title: "Title"
    )
}

// MARK: - Tests

@Suite("MDFileLoader")
struct MDFileLoaderTests {

    @Test("load returns document info from parser")
    func loadReturnsDocumentInfo() async throws {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())
        let store = MockPositionStore()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loader_test_\(UUID().uuidString).md")
        try testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.documentInfo.renderedText == testRenderedText)
        #expect(result.documentInfo.title == "Title")
        #expect(parser.parseCallCount == 1)
    }

    @Test("load restores saved UTF-16 offset position")
    func loadRestoresSavedPosition() async throws {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())
        let store = MockPositionStore()

        let savedLocator = Locator(
            bookFingerprint: testFP,
            href: nil, progression: nil, totalProgression: 0.5,
            cfi: nil, page: nil,
            charOffsetUTF16: 25,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        await store.seed(bookFingerprintKey: testFP.canonicalKey, locator: savedLocator)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore_test_\(UUID().uuidString).md")
        try testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.restoredOffsetUTF16 == 25)
    }

    @Test("load falls back to offset 0 with no saved position")
    func loadFallsBackToZero() async throws {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())
        let store = MockPositionStore()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fallback_test_\(UUID().uuidString).md")
        try testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.restoredOffsetUTF16 == 0)
    }

    @Test("load clamps saved offset beyond text length")
    func loadClampsOversizedOffset() async throws {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())
        let store = MockPositionStore()

        let savedLocator = Locator(
            bookFingerprint: testFP,
            href: nil, progression: nil, totalProgression: 1.0,
            cfi: nil, page: nil,
            charOffsetUTF16: 999999,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        await store.seed(bookFingerprintKey: testFP.canonicalKey, locator: savedLocator)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clamp_test_\(UUID().uuidString).md")
        try testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        let expectedMax = (testRenderedText as NSString).length
        #expect(result.restoredOffsetUTF16 == expectedMax)
    }

    @Test("load falls back on position store error")
    func loadFallsBackOnStoreError() async throws {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())
        let store = MockPositionStore()
        await store.setLoadError(NSError(domain: "test", code: 1))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("error_test_\(UUID().uuidString).md")
        try testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.restoredOffsetUTF16 == 0)
    }

    @Test("load throws on file read error")
    func loadThrowsOnFileError() async {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())
        let store = MockPositionStore()

        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).md")

        do {
            _ = try await MDFileLoader.load(
                url: url,
                parser: parser,
                positionStore: store,
                bookFingerprintKey: testFP.canonicalKey
            )
            Issue.record("Expected load to throw")
        } catch {
            // Any error is expected — file doesn't exist
        }
    }

    @Test("load handles empty document")
    func loadEmptyDocument() async throws {
        let emptyInfo = MDDocumentInfo(
            renderedText: "",
            renderedAttributedString: NSAttributedString(string: ""),
            headings: [],
            title: nil
        )
        let parser = MockMDParser()
        parser.setDocumentInfo(emptyInfo)
        let store = MockPositionStore()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty_test_\(UUID().uuidString).md")
        try "".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.documentInfo.renderedText == "")
        #expect(result.documentInfo.renderedTextLengthUTF16 == 0)
        #expect(result.restoredOffsetUTF16 == 0)
    }
}
