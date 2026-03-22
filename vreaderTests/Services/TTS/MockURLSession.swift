// Purpose: Test helpers for HTTP-based TTS provider tests.
// MockURLSession returns predefined responses without real networking.
// TTSProgressCollector collects chunked synthesis progress in a thread-safe way.
//
// @coordinates-with: HTTPTTSProviderTests.swift, HTTPTTSConfigTests.swift

import Foundation
@testable import vreader

/// Mock URLSession that returns predefined responses without real networking.
final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    let responseData: Data?
    let statusCode: Int
    let error: Error?
    let delay: TimeInterval

    private(set) var requestCount = 0
    private(set) var lastRequest: URLRequest?

    init(
        responseData: Data? = nil,
        statusCode: Int = 200,
        error: Error? = nil,
        delay: TimeInterval = 0
    ) {
        self.responseData = responseData
        self.statusCode = statusCode
        self.error = error
        self.delay = delay
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        requestCount += 1

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if let error = error {
            throw error
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!

        return (responseData ?? Data(), response)
    }
}

// MARK: - TTSProgressCollector

/// Thread-safe collector for chunk progress updates in tests.
final class TTSProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _updates: [(chunkIndex: Int, totalChunks: Int)] = []

    var updates: [(chunkIndex: Int, totalChunks: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return _updates
    }

    func append(chunkIndex: Int, totalChunks: Int) {
        lock.lock()
        _updates.append((chunkIndex: chunkIndex, totalChunks: totalChunks))
        lock.unlock()
    }
}
