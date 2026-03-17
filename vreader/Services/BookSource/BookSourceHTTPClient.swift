// Purpose: HTTP client for BookSource web scraping.
// URLSession-based with encoding detection, custom headers, and rate limiting.
//
// Key decisions:
// - Actor-isolated for thread safety (concurrent scraping from multiple sources).
// - Encoding detection: HTTP Content-Type → HTML meta charset → BOM → UTF-8.
// - Rate limiting via async sleep between requests (configurable per-source).
// - Custom headers from BookSource.header field (User-Agent, Referer, etc.).
// - Default User-Agent to avoid bot detection.
//
// @coordinates-with: WebPageEncodingDetector.swift, BookSourcePipeline.swift

import Foundation

/// Errors from BookSource HTTP operations.
enum HTTPClientError: Error, Equatable {
    /// HTTP response with non-2xx status code.
    case httpError(Int)

    /// Network-level error (timeout, DNS, connection refused).
    case networkError(String)

    /// Failed to decode response body with detected encoding.
    case decodingFailed(String)
}

/// HTTP client for fetching web pages and downloading files for BookSource scraping.
///
/// Actor-isolated to safely handle concurrent requests and rate limiting state.
/// Uses URLSession (not WKWebView) for headless scraping.
actor BookSourceHTTPClient {

    // MARK: - Properties

    private let session: URLSession
    private let rateLimitDelay: TimeInterval
    private let defaultTimeout: TimeInterval

    /// Timestamp of the last request, for rate limiting.
    private var lastRequestTime: ContinuousClock.Instant?

    /// Default User-Agent string to reduce bot detection.
    private static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) VReader/1.0 Mobile/15E148 Safari/604.1"

    // MARK: - Init

    /// Creates a new HTTP client.
    ///
    /// - Parameters:
    ///   - session: URLSession to use (injectable for testing).
    ///   - rateLimitDelay: Minimum seconds between requests (default 0 = no limit).
    ///   - timeout: Request timeout in seconds (default 30).
    init(
        session: URLSession = .shared,
        rateLimitDelay: TimeInterval = 0,
        timeout: TimeInterval = 30
    ) {
        self.session = session
        self.rateLimitDelay = rateLimitDelay
        self.defaultTimeout = timeout
    }

    // MARK: - Fetch Page

    /// Fetches a web page and returns decoded HTML string.
    ///
    /// Encoding detection order:
    /// 1. Explicit `encoding` parameter (if provided, skips auto-detection)
    /// 2. HTTP Content-Type charset header
    /// 3. HTML `<meta charset>` tag
    /// 4. BOM (Byte Order Mark)
    /// 5. Default: UTF-8
    ///
    /// - Parameters:
    ///   - url: Page URL to fetch.
    ///   - headers: Custom HTTP headers (User-Agent, Referer, etc.).
    ///   - encoding: Explicit encoding override. If nil, auto-detects.
    /// - Returns: Decoded HTML string.
    /// - Throws: `HTTPClientError` on failure.
    func fetchPage(
        url: URL,
        headers: [String: String]? = nil,
        encoding: String.Encoding? = nil
    ) async throws -> String {
        // Rate limiting
        await enforceRateLimit()

        // Build request
        var request = URLRequest(url: url, timeoutInterval: defaultTimeout)
        request.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")

        // Apply custom headers (may override default User-Agent)
        if let headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Execute request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPClientError.networkError(error.localizedDescription)
        }

        // Record request time for rate limiting
        lastRequestTime = .now

        // Check HTTP status
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw HTTPClientError.httpError(httpResponse.statusCode)
        }

        // Empty response
        if data.isEmpty { return "" }

        // Determine encoding
        let resolvedEncoding: String.Encoding
        if let explicit = encoding {
            resolvedEncoding = explicit
        } else {
            let contentType = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Type")
            resolvedEncoding = WebPageEncodingDetector.detect(
                data: data,
                contentTypeHeader: contentType
            )
        }

        // Decode
        guard let text = WebPageEncodingDetector.decode(
            data: data,
            encoding: resolvedEncoding
        ) else {
            throw HTTPClientError.decodingFailed(
                "Failed to decode response from \(url) with encoding \(resolvedEncoding)"
            )
        }

        return text
    }

    // MARK: - Download File

    /// Downloads a file from the given URL and saves it to the destination path.
    ///
    /// - Parameters:
    ///   - url: File URL to download.
    ///   - destination: Local file URL to save to.
    /// - Throws: `HTTPClientError` on failure.
    func downloadFile(url: URL, to destination: URL) async throws {
        await enforceRateLimit()

        var request = URLRequest(url: url, timeoutInterval: defaultTimeout * 4)
        request.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPClientError.networkError(error.localizedDescription)
        }

        lastRequestTime = .now

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw HTTPClientError.httpError(httpResponse.statusCode)
        }

        try data.write(to: destination, options: .atomic)
    }

    // MARK: - Private: Rate Limiting

    /// Waits if needed to respect the rate limit delay between requests.
    private func enforceRateLimit() async {
        guard rateLimitDelay > 0, let last = lastRequestTime else { return }

        let elapsed = ContinuousClock.now - last
        let required = Duration.seconds(rateLimitDelay)

        if elapsed < required {
            let remaining = required - elapsed
            try? await Task.sleep(for: remaining)
        }
    }
}
