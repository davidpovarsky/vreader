// Purpose: HTTP client for fetching OPDS 1.2 catalog feeds and downloading books.
// Uses URLSession for networking. Supports basic auth for private catalogs.
//
// Key decisions:
// - Async/await API with Swift concurrency.
// - Basic auth via Authorization header (not URL-embedded credentials).
// - Download saves to temp directory; caller moves to final location.
// - Timeout configurable (default 30s for feeds, 120s for downloads).
//
// @coordinates-with: OPDSParser.swift, OPDSModels.swift, BookImporter.swift

import Foundation

/// HTTP client for OPDS catalog operations.
final class OPDSClient: Sendable {

    private let session: URLSession
    private let feedTimeout: TimeInterval
    private let downloadTimeout: TimeInterval

    init(
        session: URLSession = .shared,
        feedTimeout: TimeInterval = 30,
        downloadTimeout: TimeInterval = 120
    ) {
        self.session = session
        self.feedTimeout = feedTimeout
        self.downloadTimeout = downloadTimeout
    }

    // MARK: - Fetch Feed

    /// Fetches and parses an OPDS feed from the given URL.
    ///
    /// - Parameters:
    ///   - url: The feed URL.
    ///   - credentials: Optional basic auth credentials.
    /// - Returns: Parsed OPDSFeed.
    /// - Throws: OPDSParserError for network or parsing failures.
    func fetchFeed(
        url: URL,
        credentials: OPDSCredentials? = nil
    ) async throws -> OPDSFeed {
        var request = URLRequest(url: url, timeoutInterval: feedTimeout)
        request.setValue("application/atom+xml;q=0.9, application/xml;q=0.8, */*;q=0.1",
                         forHTTPHeaderField: "Accept")

        if let creds = credentials {
            request.setValue(creds.authHeaderValue, forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OPDSParserError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw OPDSParserError.httpError(httpResponse.statusCode)
        }

        return try OPDSParser.parse(data: data, baseURL: url)
    }

    // MARK: - Download Book

    /// Downloads a book from the given URL to a temporary file.
    ///
    /// - Parameters:
    ///   - url: The acquisition URL.
    ///   - credentials: Optional basic auth credentials.
    /// - Returns: URL to the downloaded temporary file.
    /// - Throws: OPDSParserError for network failures.
    func downloadBook(
        url: URL,
        credentials: OPDSCredentials? = nil
    ) async throws -> URL {
        var request = URLRequest(url: url, timeoutInterval: downloadTimeout)

        if let creds = credentials {
            request.setValue(creds.authHeaderValue, forHTTPHeaderField: "Authorization")
        }

        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(for: request)
        } catch {
            throw OPDSParserError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw OPDSParserError.httpError(httpResponse.statusCode)
        }

        return tempURL
    }
}

// MARK: - Credentials

/// Basic auth credentials for OPDS catalogs.
struct OPDSCredentials: Sendable {
    let username: String
    let password: String

    var authHeaderValue: String {
        let cred = "\(username):\(password)"
        let encoded = Data(cred.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }
}
