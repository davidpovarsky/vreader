// Purpose: Shared protocol for TTS providers (system and HTTP-based).
// Defines the interface for synthesizing text to audio data.
//
// Key decisions:
// - Async/throws for network-based providers.
// - Chunked synthesis with progress callback for long texts.
// - Sendable for safe use across concurrency contexts.
// - Error type covers network, HTTP, cancellation, and config issues.
//
// @coordinates-with: HTTPTTSProvider.swift, TTSService.swift

import Foundation

// MARK: - TTSProvider Protocol

/// Protocol for text-to-speech providers that return audio data.
/// System TTS (AVSpeechSynthesizer) does not conform — it uses a separate path.
/// HTTP-based TTS providers conform to this protocol.
protocol TTSProvider: Sendable {
    /// Synthesizes a single text segment into audio data.
    func synthesize(text: String, voice: String) async throws -> Data

    /// Synthesizes text in chunks, calling onChunk for each completed chunk.
    /// Parameters: chunkIndex, totalChunks, audioData
    func synthesizeChunked(
        text: String,
        voice: String,
        onChunk: @Sendable (Int, Int, Data) -> Void
    ) async throws

    /// Cancels any in-progress synthesis.
    func cancel()

    /// Whether the provider has been cancelled.
    var isCancelled: Bool { get }
}

// MARK: - TTSProviderError

/// Errors from TTS provider operations.
enum TTSProviderError: Error, Equatable, Sendable {
    /// Network request failed.
    case networkError(String)

    /// HTTP response returned a non-2xx status code.
    case httpError(Int)

    /// Synthesis was cancelled.
    case cancelled

    /// Configuration is invalid.
    case invalidConfig(String)

    /// No audio data in response.
    case emptyResponse
}

// MARK: - URLSessionProtocol

/// Protocol abstracting URLSession for testability.
protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// URLSession conforms to URLSessionProtocol.
extension URLSession: URLSessionProtocol {}
