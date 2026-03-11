// Purpose: Tests for TXTFileLoader — verifies service open + position restore
// logic extracted from TXTReaderViewModel in WI-008d.
//
// @coordinates-with: TXTFileLoader.swift, TXTServiceProtocol.swift, MockTXTService.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let testFP = DocumentFingerprint(
    contentSHA256: "txt_loader_test_sha256_0000000000000000000000000000000000000",
    fileByteCount: 1000,
    format: .txt
)

private let testText = "Hello world. This is a test document with some words for reading."
private let testMetadata = TXTFileMetadata(
    text: testText,
    fileByteCount: 1000,
    detectedEncoding: "UTF-8",
    totalTextLengthUTF16: (testText as NSString).length,
    totalWordCount: 12
)

private let testURL = URL(fileURLWithPath: "/tmp/loader-test.txt")

// MARK: - Tests

@Suite("TXTFileLoader")
struct TXTFileLoaderTests {

    @Test("load returns metadata from service")
    func loadReturnsMetadata() async throws {
        let service = MockTXTService()
        await service.setMetadata(testMetadata)
        let store = MockPositionStore()

        let result = try await TXTFileLoader.load(
            url: testURL,
            service: service,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.metadata.text == testText)
        #expect(result.metadata.totalWordCount == 12)
        let openCount = await service.openCallCount
        #expect(openCount == 1)
    }

    @Test("load restores saved UTF-16 offset position")
    func loadRestoresSavedPosition() async throws {
        let service = MockTXTService()
        await service.setMetadata(testMetadata)
        let store = MockPositionStore()

        guard let savedLocator = LocatorFactory.txtPosition(
            fingerprint: testFP,
            charOffsetUTF16: 20,
            sourceText: testText
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await store.seed(bookFingerprintKey: testFP.canonicalKey, locator: savedLocator)

        let result = try await TXTFileLoader.load(
            url: testURL,
            service: service,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.restoredOffsetUTF16 == 20)
        #expect(result.hadSavedPosition == true)
    }

    @Test("load falls back to offset 0 with no saved position")
    func loadFallsBackToZero() async throws {
        let service = MockTXTService()
        await service.setMetadata(testMetadata)
        let store = MockPositionStore()

        let result = try await TXTFileLoader.load(
            url: testURL,
            service: service,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.restoredOffsetUTF16 == 0)
        #expect(result.hadSavedPosition == false)
    }

    @Test("load clamps saved offset beyond text length")
    func loadClampsOversizedOffset() async throws {
        let service = MockTXTService()
        await service.setMetadata(testMetadata)
        let store = MockPositionStore()

        guard let savedLocator = LocatorFactory.txtPosition(
            fingerprint: testFP,
            charOffsetUTF16: 99999
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await store.seed(bookFingerprintKey: testFP.canonicalKey, locator: savedLocator)

        let result = try await TXTFileLoader.load(
            url: testURL,
            service: service,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.restoredOffsetUTF16 == testMetadata.totalTextLengthUTF16)
    }

    @Test("load falls back on position store error")
    func loadFallsBackOnStoreError() async throws {
        let service = MockTXTService()
        await service.setMetadata(testMetadata)
        let store = MockPositionStore()
        await store.setLoadError(NSError(domain: "test", code: 1))

        let result = try await TXTFileLoader.load(
            url: testURL,
            service: service,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.restoredOffsetUTF16 == 0)
        #expect(result.hadSavedPosition == false)
    }

    @Test("load throws on service error preserving original type")
    func loadThrowsServiceError() async {
        let service = MockTXTService()
        await service.setMetadata(testMetadata)
        await service.setOpenError(.fileNotFound("/tmp/bad.txt"))
        let store = MockPositionStore()

        do {
            _ = try await TXTFileLoader.load(
                url: testURL,
                service: service,
                positionStore: store,
                bookFingerprintKey: testFP.canonicalKey
            )
            Issue.record("Expected load to throw")
        } catch let error as TXTServiceError {
            #expect(error == .fileNotFound("/tmp/bad.txt"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("load handles empty file")
    func loadEmptyFile() async throws {
        let emptyMeta = TXTFileMetadata(
            text: "",
            fileByteCount: 0,
            detectedEncoding: "UTF-8",
            totalTextLengthUTF16: 0,
            totalWordCount: 0
        )
        let service = MockTXTService()
        await service.setMetadata(emptyMeta)
        let store = MockPositionStore()

        let result = try await TXTFileLoader.load(
            url: testURL,
            service: service,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.metadata.text == "")
        #expect(result.metadata.totalTextLengthUTF16 == 0)
        #expect(result.restoredOffsetUTF16 == 0)
    }
}
