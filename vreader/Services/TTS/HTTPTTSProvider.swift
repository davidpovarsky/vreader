// Purpose: HTTP-based TTS provider for cloud voice synthesis (Azure, custom APIs).
// Sends text to a REST endpoint, receives audio data, and supports chunked synthesis,
// disk caching, and position tracking.
//
// Key decisions:
// - URLSession-based with protocol abstraction for testability.
// - Text chunked at sentence boundaries (.!?。！？) for natural audio segments.
// - Long sentences (>500 chars) split at word/character boundaries.
// - Disk cache keyed by SHA-256 hash of text+voice to skip duplicate requests.
// - Cancellation via Task cooperative cancellation + isCancelled flag.
// - Azure SSML format for Azure provider; JSON body for custom providers.
//
// @coordinates-with: TTSProviderProtocol.swift, HTTPTTSConfig.swift, TTSService.swift

import Foundation
import CryptoKit

// MARK: - HTTPTTSProvider

/// HTTP-based TTS provider that synthesizes text via a cloud API.
final class HTTPTTSProvider: TTSProvider, @unchecked Sendable {

    /// Maximum characters per chunk before forced splitting.
    static let maxChunkLength = 500

    private let config: HTTPTTSConfig
    private let urlSession: URLSessionProtocol
    private let cacheDirectory: URL?
    private var _isCancelled = false
    private let lock = NSLock()

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    // MARK: - Init

    /// Creates an HTTPTTSProvider with the given configuration.
    ///
    /// - Parameters:
    ///   - config: TTS API configuration (endpoint, key, voice).
    ///   - urlSession: URL session for network requests (injectable for tests).
    ///   - cacheDirectory: Optional directory for disk caching audio chunks.
    init(
        config: HTTPTTSConfig,
        urlSession: URLSessionProtocol = URLSession.shared,
        cacheDirectory: URL? = nil
    ) {
        self.config = config
        self.urlSession = urlSession
        self.cacheDirectory = cacheDirectory
    }

    // MARK: - TTSProvider

    func synthesize(text: String, voice: String) async throws -> Data {
        // Check cache first
        if let cached = loadFromCache(text: text, voice: voice) {
            return cached
        }

        let request = try buildRequest(text: text, voice: voice)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw TTSProviderError.cancelled
        } catch {
            throw TTSProviderError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSProviderError.networkError("Invalid response type")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TTSProviderError.httpError(httpResponse.statusCode)
        }

        guard !data.isEmpty else {
            throw TTSProviderError.emptyResponse
        }

        // Save to cache
        saveToCache(text: text, voice: voice, data: data)

        return data
    }

    func synthesizeChunked(
        text: String,
        voice: String,
        onChunk: @Sendable (Int, Int, Data) -> Void
    ) async throws {
        let chunks = Self.chunkText(text)
        guard !chunks.isEmpty else { return }

        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()

            if isCancelled { throw TTSProviderError.cancelled }

            let audioData = try await synthesize(text: chunk, voice: voice)
            onChunk(index, chunks.count, audioData)
        }
    }

    func cancel() {
        lock.lock()
        _isCancelled = true
        lock.unlock()
    }

    // MARK: - Text Chunking

    /// Splits text into chunks at sentence boundaries.
    /// Sentence terminators: `.` `!` `?` `。` `！` `？`
    /// Chunks longer than `maxChunkLength` are split further.
    static func chunkText(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Split at sentence-ending punctuation, keeping the punctuation with the sentence
        let terminators: Set<Character> = [".", "!", "?", "\u{3002}", "\u{FF01}", "\u{FF1F}"]
        var chunks: [String] = []
        var current = ""

        for char in trimmed {
            current.append(char)
            if terminators.contains(char) {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    chunks.append(sentence)
                }
                current = ""
            }
        }

        // Remaining text without sentence terminator
        let remaining = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            chunks.append(remaining)
        }

        // Split oversized chunks
        return chunks.flatMap { splitLongChunk($0) }
    }

    /// Splits a single chunk that exceeds maxChunkLength.
    private static func splitLongChunk(_ text: String) -> [String] {
        guard text.count > maxChunkLength else { return [text] }

        var result: [String] = []
        var startIdx = text.startIndex

        while startIdx < text.endIndex {
            let remaining = text.distance(from: startIdx, to: text.endIndex)
            let chunkSize = min(remaining, maxChunkLength)
            let endIdx = text.index(startIdx, offsetBy: chunkSize)

            // Try to split at a word boundary (space) for Latin text
            var splitIdx = endIdx
            if endIdx < text.endIndex {
                let searchRange = startIdx..<endIdx
                if let lastSpace = text[searchRange].lastIndex(of: " "),
                   text.distance(from: startIdx, to: lastSpace) > maxChunkLength / 2 {
                    splitIdx = text.index(after: lastSpace)
                }
            }

            let chunk = String(text[startIdx..<splitIdx])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                result.append(chunk)
            }
            startIdx = splitIdx
        }

        return result
    }

    // MARK: - Request Building

    private func buildRequest(text: String, voice: String) throws -> URLRequest {
        guard let url = URL(string: config.endpoint) else {
            throw TTSProviderError.invalidConfig("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        switch config.provider {
        case .azure(let region):
            request = buildAzureRequest(request: request, text: text, voice: voice, region: region)
        case .custom(let headers, let bodyTemplate):
            request = buildCustomRequest(
                request: request, text: text, voice: voice,
                headers: headers, bodyTemplate: bodyTemplate
            )
        }

        return request
    }

    private func buildAzureRequest(
        request: URLRequest,
        text: String,
        voice: String,
        region: String
    ) -> URLRequest {
        var req = request
        req.setValue(config.apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        req.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        req.setValue("audio-16khz-128kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")

        // Build SSML body
        let escapedText = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let ssml = """
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>
            <voice name='\(voice)'>\(escapedText)</voice>
        </speak>
        """
        req.httpBody = Data(ssml.utf8)
        return req
    }

    private func buildCustomRequest(
        request: URLRequest,
        text: String,
        voice: String,
        headers: [String: String],
        bodyTemplate: String
    ) -> URLRequest {
        var req = request
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }

        let body = bodyTemplate
            .replacingOccurrences(of: "{{TEXT}}", with: text)
            .replacingOccurrences(of: "{{VOICE}}", with: voice)
        req.httpBody = Data(body.utf8)

        if req.value(forHTTPHeaderField: "Content-Type") == nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return req
    }

    // MARK: - Disk Cache

    private func cacheKey(text: String, voice: String) -> String {
        let input = "\(text)|\(voice)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func loadFromCache(text: String, voice: String) -> Data? {
        guard let dir = cacheDirectory else { return nil }
        let key = cacheKey(text: text, voice: voice)
        let filePath = dir.appendingPathComponent("\(key).mp3")
        return try? Data(contentsOf: filePath)
    }

    private func saveToCache(text: String, voice: String, data: Data) {
        guard let dir = cacheDirectory else { return }
        let key = cacheKey(text: text, voice: voice)
        let filePath = dir.appendingPathComponent("\(key).mp3")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: filePath, options: .atomic)
    }
}
