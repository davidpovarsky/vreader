// Purpose: Tests for HTTPTTSProvider — HTTP-based TTS with chunking, caching, and fallback.
// Validates synthesis, text chunking, caching, position tracking, cancellation,
// network error fallback, and Azure-specific headers.
//
// Key decisions:
// - Uses MockURLSession to avoid real network in tests.
// - Tests run synchronously where possible via direct state inspection.
// - Edge cases: empty text, CJK sentence splitting, very long text, rapid cancellation.

import Testing
import Foundation
@testable import vreader

// MARK: - Synthesis Tests

@Suite("HTTPTTSProvider Synthesis")
struct HTTPTTSProviderSynthesisTests {

    @Test
    func synthesize_returnsAudioData() async throws {
        let audioData = Data("fake-audio-bytes".utf8)
        let session = MockURLSession(responseData: audioData, statusCode: 200)
        let config = HTTPTTSConfig(
            endpoint: "https://api.example.com/tts",
            apiKey: "test-key-123",
            voice: "en-US-JennyNeural"
        )
        let provider = HTTPTTSProvider(config: config, urlSession: session)
        let result = try await provider.synthesize(text: "Hello world", voice: "en-US-JennyNeural")
        #expect(result == audioData)
    }

    @Test
    func networkError_throws() async throws {
        let session = MockURLSession(error: URLError(.notConnectedToInternet))
        let config = HTTPTTSConfig(
            endpoint: "https://api.example.com/tts",
            apiKey: "test-key-123",
            voice: "en-US-JennyNeural"
        )
        let provider = HTTPTTSProvider(config: config, urlSession: session)
        do {
            _ = try await provider.synthesize(text: "Hello", voice: "en-US-JennyNeural")
            Issue.record("Should have thrown TTSProviderError.networkError")
        } catch is TTSProviderError {
            // Expected
        }
    }

    @Test
    func synthesize_httpError_throws() async throws {
        let session = MockURLSession(responseData: Data(), statusCode: 401)
        let config = HTTPTTSConfig(
            endpoint: "https://api.example.com/tts",
            apiKey: "bad-key",
            voice: "en-US-JennyNeural"
        )
        let provider = HTTPTTSProvider(config: config, urlSession: session)
        do {
            _ = try await provider.synthesize(text: "Hello", voice: "en-US-JennyNeural")
            Issue.record("Should have thrown on HTTP 401")
        } catch let error as TTSProviderError {
            if case .httpError(let code) = error {
                #expect(code == 401)
            } else {
                Issue.record("Expected httpError, got \(error)")
            }
        }
    }
}

// MARK: - Text Chunking Tests

@Suite("HTTPTTSProvider Text Chunking")
struct HTTPTTSProviderChunkingTests {

    @Test func chunkText_intoSentences() {
        let text = "Hello world. How are you? I am fine! Thanks."
        let chunks = HTTPTTSProvider.chunkText(text)
        #expect(chunks.count == 4)
        #expect(chunks[0] == "Hello world.")
        #expect(chunks[1] == "How are you?")
        #expect(chunks[2] == "I am fine!")
        #expect(chunks[3] == "Thanks.")
    }

    @Test func chunkText_cjkSentences() {
        let text = "你好世界。今天天气怎么样？很好！谢谢。"
        let chunks = HTTPTTSProvider.chunkText(text)
        #expect(chunks.count == 4)
        #expect(chunks[0] == "你好世界。")
        #expect(chunks[1] == "今天天气怎么样？")
        #expect(chunks[2] == "很好！")
        #expect(chunks[3] == "谢谢。")
    }

    @Test func chunkText_emptyText_returnsEmpty() {
        #expect(HTTPTTSProvider.chunkText("").isEmpty)
    }

    @Test func chunkText_whitespaceOnly_returnsEmpty() {
        #expect(HTTPTTSProvider.chunkText("   \n\t  ").isEmpty)
    }

    @Test func chunkText_noSentenceTerminator_returnsSingleChunk() {
        let chunks = HTTPTTSProvider.chunkText("Hello world without punctuation")
        #expect(chunks.count == 1)
        #expect(chunks[0] == "Hello world without punctuation")
    }

    @Test func chunkText_singleCharacter() {
        let chunks = HTTPTTSProvider.chunkText("A")
        #expect(chunks.count == 1)
        #expect(chunks[0] == "A")
    }

    @Test func chunkText_longSentence_splitsAtMaxLength() {
        let longWord = String(repeating: "a", count: 600)
        let chunks = HTTPTTSProvider.chunkText(longWord)
        #expect(chunks.count >= 2, "Long text should be split at maxChunkLength")
        for chunk in chunks {
            #expect(chunk.count <= HTTPTTSProvider.maxChunkLength)
        }
    }

    @Test func chunkText_mixedCJKAndLatin() {
        let text = "Hello world. 你好世界。How are you?"
        let chunks = HTTPTTSProvider.chunkText(text)
        #expect(chunks.count == 3)
        #expect(chunks[0] == "Hello world.")
        #expect(chunks[1] == "你好世界。")
        #expect(chunks[2] == "How are you?")
    }

    @Test func chunkText_consecutivePunctuation() {
        let text = "Really?! Yes... No."
        let chunks = HTTPTTSProvider.chunkText(text)
        for chunk in chunks {
            #expect(!chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "No empty chunks should be produced")
        }
    }
}

// MARK: - Cancellation Tests

@Suite("HTTPTTSProvider Cancellation")
struct HTTPTTSProviderCancellationTests {

    @Test
    func cancelDuringSynthesis_stops() async throws {
        let session = MockURLSession(
            responseData: Data("audio".utf8), statusCode: 200, delay: 5.0
        )
        let config = HTTPTTSConfig(
            endpoint: "https://api.example.com/tts",
            apiKey: "test-key",
            voice: "en-US-JennyNeural"
        )
        let provider = HTTPTTSProvider(config: config, urlSession: session)

        let task = Task {
            try await provider.synthesize(text: "Hello world", voice: "en-US-JennyNeural")
        }

        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        provider.cancel()
        task.cancel()

        _ = await task.result  // Let it complete
        #expect(provider.isCancelled, "Provider should be marked as cancelled")
    }
}

// MARK: - Cache Tests

@Suite("HTTPTTSProvider Caching")
struct HTTPTTSProviderCacheTests {

    @Test
    func cacheAudio_skipsDuplicateRequest() async throws {
        let audioData = Data("cached-audio".utf8)
        let session = MockURLSession(responseData: audioData, statusCode: 200)
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tts-cache-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let config = HTTPTTSConfig(
            endpoint: "https://api.example.com/tts",
            apiKey: "test-key",
            voice: "en-US-JennyNeural"
        )
        let provider = HTTPTTSProvider(
            config: config, urlSession: session, cacheDirectory: cacheDir
        )

        let result1 = try await provider.synthesize(text: "Hello", voice: "en-US-JennyNeural")
        #expect(result1 == audioData)
        #expect(session.requestCount == 1)

        let result2 = try await provider.synthesize(text: "Hello", voice: "en-US-JennyNeural")
        #expect(result2 == audioData)
        #expect(session.requestCount == 1, "Second request should use cache")
    }
}

// MARK: - Position Tracking Tests

@Suite("HTTPTTSProvider Position Tracking")
struct HTTPTTSProviderPositionTests {

    @Test
    func positionTracking_matchesChunkProgress() async throws {
        let audioData = Data("audio-chunk".utf8)
        let session = MockURLSession(responseData: audioData, statusCode: 200)
        let config = HTTPTTSConfig(
            endpoint: "https://api.example.com/tts",
            apiKey: "test-key",
            voice: "en-US-JennyNeural"
        )
        let provider = HTTPTTSProvider(config: config, urlSession: session)

        let collector = TTSProgressCollector()

        try await provider.synthesizeChunked(
            text: "Hello. World. Test.",
            voice: "en-US-JennyNeural"
        ) { chunkIndex, totalChunks, _ in
            collector.append(chunkIndex: chunkIndex, totalChunks: totalChunks)
        }

        let updates = collector.updates
        #expect(updates.count == 3)
        #expect(updates[0].chunkIndex == 0)
        #expect(updates[0].totalChunks == 3)
        #expect(updates[1].chunkIndex == 1)
        #expect(updates[2].chunkIndex == 2)
    }
}

// MARK: - Azure API Tests

@Suite("HTTPTTSProvider Azure API")
struct HTTPTTSProviderAzureTests {

    @Test
    func azureAPI_correctHeaders() async throws {
        let audioData = Data("azure-audio".utf8)
        let session = MockURLSession(responseData: audioData, statusCode: 200)
        let config = HTTPTTSConfig(
            endpoint: "https://eastus.tts.speech.microsoft.com/cognitiveservices/v1",
            apiKey: "azure-key-123",
            voice: "en-US-JennyNeural",
            provider: .azure(region: "eastus")
        )
        let provider = HTTPTTSProvider(config: config, urlSession: session)

        _ = try await provider.synthesize(text: "Hello", voice: "en-US-JennyNeural")

        let request = session.lastRequest
        #expect(request != nil)
        #expect(request?.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "azure-key-123")
        #expect(request?.value(forHTTPHeaderField: "Content-Type") == "application/ssml+xml")
        #expect(request?.value(forHTTPHeaderField: "X-Microsoft-OutputFormat") == "audio-16khz-128kbitrate-mono-mp3")
    }

    @Test
    func customEndpoint_configurable() async throws {
        let audioData = Data("custom-audio".utf8)
        let session = MockURLSession(responseData: audioData, statusCode: 200)
        let config = HTTPTTSConfig(
            endpoint: "https://my-custom-tts.example.com/api/speak",
            apiKey: "custom-key",
            voice: "my-custom-voice",
            provider: .custom(
                headers: ["Authorization": "Bearer custom-key"],
                bodyTemplate: "{\"text\": \"{{TEXT}}\", \"voice\": \"{{VOICE}}\"}"
            )
        )
        let provider = HTTPTTSProvider(config: config, urlSession: session)

        _ = try await provider.synthesize(text: "Test", voice: "my-custom-voice")

        let request = session.lastRequest
        #expect(request?.url?.absoluteString == "https://my-custom-tts.example.com/api/speak")
    }
}
