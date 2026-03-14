// Purpose: ViewModel for the AI Settings section.
// Manages feature flag toggle, API key validation/persistence, consent state,
// and AI configuration (model, temperature, base URL, max tokens).
//
// Key decisions:
// - @Observable for SwiftUI binding (iOS 17+).
// - Dependencies injected for testability (FeatureFlags, KeychainService, etc.).
// - API key trimmed before validation and storage.
// - Temperature clamped to 0.0–2.0, maxTokens clamped to 1–128_000.
// - Base URL validated as parseable URL before saving.
// - Saves configuration to AIConfigurationStore on explicit saveConfiguration() call.
//
// @coordinates-with: FeatureFlags.swift, KeychainService.swift,
//   AIConsentManager.swift, AIConfigurationStore.swift

import Foundation
import Observation

/// ViewModel for the AI settings screen.
@Observable
@MainActor
final class AISettingsViewModel {

    // MARK: - Dependencies

    private let featureFlags: FeatureFlags
    private let consentManager: AIConsentManager
    private let keychainService: KeychainService
    private let configurationStore: AIConfigurationStore

    // MARK: - Published State

    /// Whether the AI assistant feature flag is enabled.
    var isAIEnabled: Bool {
        get { featureFlags.isEnabled(.aiAssistant) }
        set { featureFlags.setOverride(newValue, for: .aiAssistant) }
    }

    /// The current API key input (not persisted until saveAPIKey() is called).
    var apiKeyInput: String = ""

    /// Error message for API key validation.
    var apiKeyError: String?

    /// Whether an API key is currently saved in the Keychain.
    var isAPIKeySaved: Bool

    /// Whether the user has granted AI data consent.
    var hasConsent: Bool {
        get { consentManager.hasConsent }
        set {
            if newValue {
                consentManager.grantConsent()
            } else {
                consentManager.revokeConsent()
            }
        }
    }

    /// The AI model identifier.
    var model: String

    /// Sampling temperature (clamped to 0.0–2.0).
    var temperature: Double

    /// Maximum response tokens (clamped to 1–128_000).
    var maxTokens: Int

    /// The provider API base URL string.
    var baseURL: String

    /// Error message for base URL validation.
    var baseURLError: String?

    // MARK: - Constants

    private static let temperatureRange: ClosedRange<Double> = 0.0...2.0
    private static let maxTokensRange: ClosedRange<Int> = 1...128_000

    // MARK: - Initialization

    /// Creates an AI settings ViewModel with injected dependencies.
    ///
    /// - Parameters:
    ///   - featureFlags: Feature flags instance (defaults to .shared).
    ///   - consentManager: AI consent manager.
    ///   - keychainService: Keychain storage for API key.
    ///   - configurationStore: AI configuration persistence.
    init(
        featureFlags: FeatureFlags = .shared,
        consentManager: AIConsentManager = AIConsentManager(),
        keychainService: KeychainService = KeychainService(),
        configurationStore: AIConfigurationStore = AIConfigurationStore()
    ) {
        self.featureFlags = featureFlags
        self.consentManager = consentManager
        self.keychainService = keychainService
        self.configurationStore = configurationStore

        // Load existing API key state
        let existingKey = try? keychainService.readString(
            forAccount: AIService.apiKeyAccount
        )
        self.isAPIKeySaved = existingKey != nil && !(existingKey?.isEmpty ?? true)

        // Load existing configuration
        let config = configurationStore.load()
        self.model = config.model
        self.temperature = config.temperature
        self.maxTokens = config.maxTokens
        self.baseURL = config.endpoint.absoluteString
    }

    // MARK: - API Key Management

    /// Validates and saves the API key to the Keychain.
    /// Sets `apiKeyError` on validation failure.
    func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            apiKeyError = "API key cannot be empty."
            isAPIKeySaved = false
            return
        }

        do {
            try keychainService.saveString(trimmed, forAccount: AIService.apiKeyAccount)
            apiKeyError = nil
            isAPIKeySaved = true
        } catch {
            apiKeyError = "Failed to save API key: \(error.localizedDescription)"
            isAPIKeySaved = false
        }
    }

    /// Deletes the API key from the Keychain.
    func deleteAPIKey() {
        try? keychainService.delete(forAccount: AIService.apiKeyAccount)
        isAPIKeySaved = false
        apiKeyInput = ""
        apiKeyError = nil
    }

    // MARK: - Configuration Management

    /// Validates and saves the current configuration to the store.
    /// Clamps temperature and maxTokens to valid ranges.
    func saveConfiguration() {
        // Clamp values
        temperature = min(max(temperature, Self.temperatureRange.lowerBound),
                          Self.temperatureRange.upperBound)
        maxTokens = min(max(maxTokens, Self.maxTokensRange.lowerBound),
                        Self.maxTokensRange.upperBound)

        // Validate base URL
        guard let url = URL(string: baseURL), !baseURL.isEmpty else {
            baseURLError = "Please enter a valid URL."
            return
        }

        // Check URL has a scheme
        guard let scheme = url.scheme?.lowercased() else {
            baseURLError = "URL must include a scheme (e.g., https://)."
            return
        }

        // Require HTTPS; allow HTTP only for localhost/127.0.0.1/[::1]
        if scheme == "http" {
            let host = url.host?.lowercased() ?? ""
            let isLocalhost = host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
            if !isLocalhost {
                baseURLError = "Only HTTPS URLs are allowed. HTTP is permitted only for localhost."
                return
            }
        } else if scheme != "https" {
            baseURLError = "URL must use HTTPS (or HTTP for localhost only)."
            return
        }

        baseURLError = nil

        let config = AIConfiguration(
            model: model,
            temperature: temperature,
            endpoint: url,
            maxTokens: maxTokens
        )
        configurationStore.save(config)
    }
}
