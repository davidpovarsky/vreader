// Purpose: Mock TXT service for unit testing TXTReaderViewModel.
//
// @coordinates-with: TXTServiceProtocol.swift, TXTReaderViewModelTests.swift,
//   TXTChapterIntegrationTests.swift

import Foundation
@testable import vreader

/// In-memory mock of TXTServiceProtocol for unit tests.
actor MockTXTService: TXTServiceProtocol {
    /// Metadata to return on open. Nil triggers an error.
    var metadataToReturn: TXTFileMetadata?

    /// Chapter-based result to return on openChapterBased. Nil triggers an error.
    var chapterOpenResultToReturn: TXTChapterOpenResult?

    /// Error to throw on open.
    var openError: TXTServiceError?

    /// Error to throw on openChapterBased.
    var chapterOpenError: TXTServiceError?

    /// Whether a file is currently open.
    private(set) var _isOpen = false

    /// Count of open calls (for verifying lifecycle).
    private(set) var openCallCount = 0

    /// Count of openChapterBased calls.
    private(set) var chapterOpenCallCount = 0

    /// Count of close calls.
    private(set) var closeCallCount = 0

    var isOpen: Bool { _isOpen }

    func open(url: URL) async throws -> TXTFileMetadata {
        openCallCount += 1
        if let error = openError { throw error }
        guard let metadata = metadataToReturn else {
            throw TXTServiceError.decodingFailed("No metadata configured in mock")
        }
        _isOpen = true
        return metadata
    }

    func openChapterBased(url: URL) async throws -> TXTChapterOpenResult {
        chapterOpenCallCount += 1
        if let error = chapterOpenError { throw error }
        guard let result = chapterOpenResultToReturn else {
            throw TXTServiceError.decodingFailed("No chapter result configured in mock")
        }
        _isOpen = true
        return result
    }

    func close() async {
        closeCallCount += 1
        _isOpen = false
    }

    // MARK: - Test Helpers

    func setMetadata(_ metadata: TXTFileMetadata?) {
        metadataToReturn = metadata
    }

    func setChapterOpenResult(_ result: TXTChapterOpenResult?) {
        chapterOpenResultToReturn = result
    }

    func setOpenError(_ error: TXTServiceError?) {
        openError = error
    }

    func setChapterOpenError(_ error: TXTServiceError?) {
        chapterOpenError = error
    }
}
