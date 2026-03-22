// Purpose: Tests for HTTPTTSConfig validation.
// Validates endpoint URL, API key, voice, and edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("HTTPTTSConfig Validation")
struct HTTPTTSConfigValidationTests {

    @Test func configValidation_rejectsEmptyURL() {
        let config = HTTPTTSConfig(
            endpoint: "", apiKey: "test-key", voice: "en-US-JennyNeural"
        )
        #expect(config.validate() == .invalid(.emptyEndpoint))
    }

    @Test func configValidation_rejectsEmptyKey() {
        let config = HTTPTTSConfig(
            endpoint: "https://api.example.com/tts", apiKey: "", voice: "en-US-JennyNeural"
        )
        #expect(config.validate() == .invalid(.emptyAPIKey))
    }

    @Test func configValidation_rejectsEmptyVoice() {
        let config = HTTPTTSConfig(
            endpoint: "https://api.example.com/tts", apiKey: "test-key", voice: ""
        )
        #expect(config.validate() == .invalid(.emptyVoice))
    }

    @Test func configValidation_rejectsInvalidURL() {
        let config = HTTPTTSConfig(
            endpoint: "not a valid url", apiKey: "test-key", voice: "en-US-JennyNeural"
        )
        #expect(config.validate() == .invalid(.invalidEndpointURL))
    }

    @Test func configValidation_acceptsValidConfig() {
        let config = HTTPTTSConfig(
            endpoint: "https://api.example.com/tts",
            apiKey: "test-key-123",
            voice: "en-US-JennyNeural"
        )
        #expect(config.validate() == .valid)
    }

    @Test func configValidation_rejectsWhitespaceOnlyURL() {
        let config = HTTPTTSConfig(
            endpoint: "   ", apiKey: "test-key", voice: "en-US-JennyNeural"
        )
        #expect(config.validate() == .invalid(.emptyEndpoint))
    }

    @Test func configValidation_rejectsWhitespaceOnlyKey() {
        let config = HTTPTTSConfig(
            endpoint: "https://api.example.com/tts", apiKey: "   ", voice: "en-US-JennyNeural"
        )
        #expect(config.validate() == .invalid(.emptyAPIKey))
    }

    @Test func configValidation_rejectsNoSchemeURL() {
        let config = HTTPTTSConfig(
            endpoint: "example.com/tts", apiKey: "test-key", voice: "en-US-JennyNeural"
        )
        #expect(config.validate() == .invalid(.invalidEndpointURL))
    }

    @Test func configValidation_acceptsHTTPScheme() {
        let config = HTTPTTSConfig(
            endpoint: "http://localhost:8080/tts",
            apiKey: "test-key",
            voice: "custom-voice"
        )
        #expect(config.validate() == .valid)
    }

    @Test func configValidation_codable_roundTrip() throws {
        let config = HTTPTTSConfig(
            endpoint: "https://api.example.com/tts",
            apiKey: "test-key",
            voice: "en-US-JennyNeural",
            provider: .azure(region: "eastus")
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(HTTPTTSConfig.self, from: data)
        #expect(decoded == config)
    }

    @Test func configValidation_customProvider_codable_roundTrip() throws {
        let config = HTTPTTSConfig(
            endpoint: "https://custom.api.com/speak",
            apiKey: "key",
            voice: "voice1",
            provider: .custom(
                headers: ["Auth": "Bearer key"],
                bodyTemplate: "{\"text\":\"{{TEXT}}\"}"
            )
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(HTTPTTSConfig.self, from: data)
        #expect(decoded == config)
    }
}
