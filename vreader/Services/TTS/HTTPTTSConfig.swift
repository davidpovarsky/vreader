// Purpose: Configuration for HTTP-based TTS providers (Azure, custom endpoints).
// Stores endpoint URL, API key, voice ID, and provider-specific settings.
//
// Key decisions:
// - Codable for persistence via UserDefaults or Keychain.
// - Validation returns a typed result for UI display.
// - Provider enum distinguishes Azure from custom endpoints.
// - API key stored separately in Keychain; only the account reference is persisted.
//
// @coordinates-with: HTTPTTSProvider.swift, HTTPTTSSettingsView.swift

import Foundation

// MARK: - HTTPTTSConfig

/// Configuration for an HTTP-based TTS provider.
struct HTTPTTSConfig: Codable, Sendable, Equatable {

    /// The TTS API endpoint URL.
    var endpoint: String

    /// The API key for authentication.
    var apiKey: String

    /// The voice identifier (e.g., "en-US-JennyNeural" for Azure).
    var voice: String

    /// The provider type with provider-specific settings.
    var provider: TTSProviderType

    init(
        endpoint: String,
        apiKey: String,
        voice: String,
        provider: TTSProviderType = .azure(region: "eastus")
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.voice = voice
        self.provider = provider
    }

    // MARK: - Validation

    /// Validates the configuration and returns the result.
    func validate() -> ConfigValidationResult {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVoice = voice.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedEndpoint.isEmpty {
            return .invalid(.emptyEndpoint)
        }
        if trimmedKey.isEmpty {
            return .invalid(.emptyAPIKey)
        }
        if trimmedVoice.isEmpty {
            return .invalid(.emptyVoice)
        }
        // URL(string:) is very permissive — also check for http/https scheme
        guard let url = URL(string: trimmedEndpoint),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return .invalid(.invalidEndpointURL)
        }
        return .valid
    }
}

// MARK: - TTSProviderType

/// Identifies the TTS provider and its specific settings.
enum TTSProviderType: Codable, Sendable, Equatable {
    /// Azure Cognitive Services TTS.
    case azure(region: String)

    /// Custom REST API endpoint.
    case custom(headers: [String: String], bodyTemplate: String)
}

// MARK: - ConfigValidationResult

/// Result of validating an HTTPTTSConfig.
enum ConfigValidationResult: Equatable, Sendable {
    case valid
    case invalid(ConfigValidationError)
}

/// Specific validation errors for HTTPTTSConfig.
enum ConfigValidationError: Equatable, Sendable {
    case emptyEndpoint
    case emptyAPIKey
    case emptyVoice
    case invalidEndpointURL
}
