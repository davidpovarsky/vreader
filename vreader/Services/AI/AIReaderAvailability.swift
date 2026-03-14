// Purpose: Determines whether AI reader features are available to display in the UI.
// Encapsulates the feature-flag + API-key check so views and tests don't
// depend on AIService internals.
//
// Key decisions:
// - Pure functions with no side effects — easy to test.
// - Checks feature flag AND API key presence (both must be true).
// - Does NOT check consent — that's handled at request time.
//
// @coordinates-with: FeatureFlags.swift, KeychainService.swift, ReaderContainerView.swift

import Foundation

/// Utility to check AI feature availability for reader UI.
enum AIReaderAvailability {

    /// Returns true when the AI assistant feature is enabled AND an API key is saved.
    ///
    /// - Parameters:
    ///   - featureFlags: The feature flags instance to check.
    ///   - keychainService: The keychain service to look up the API key.
    /// - Returns: Whether the AI button should be shown in the reader toolbar.
    static func isAvailable(
        featureFlags: FeatureFlags,
        keychainService: KeychainService
    ) -> Bool {
        guard featureFlags.aiAssistant else { return false }
        return hasAPIKey(keychainService: keychainService)
    }

    /// Returns true when a non-empty API key exists in the keychain.
    ///
    /// - Parameter keychainService: The keychain service to check.
    /// - Returns: Whether an API key is saved.
    static func hasAPIKey(keychainService: KeychainService) -> Bool {
        guard let key = try? keychainService.readString(
            forAccount: AIService.apiKeyAccount
        ) else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
