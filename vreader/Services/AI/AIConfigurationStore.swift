// Purpose: Reads/writes AIConfiguration to PreferenceStore.
// Uses JSON encoding for storage, returns .default on missing or corrupt data.
//
// Key decisions:
// - Uses PreferenceStoring protocol for testability (MockPreferenceStore in tests).
// - Single key for the entire configuration blob.
// - Graceful degradation: corrupt or missing data returns AIConfiguration.default.
// - Sendable for cross-actor use.
//
// @coordinates-with: AIConfiguration.swift, PreferenceStore.swift

import Foundation

/// Persists AI configuration to PreferenceStoring.
struct AIConfigurationStore: Sendable {

    /// The storage key for the AI configuration JSON.
    private static let storageKey = "com.vreader.ai.configuration"

    /// The preference store backing this configuration store.
    private let preferences: any PreferenceStoring

    /// Creates a store backed by the given preference storage.
    ///
    /// - Parameter preferences: The preference store to use.
    ///   Defaults to UserDefaultsPreferenceStore.
    init(preferences: any PreferenceStoring = UserDefaultsPreferenceStore()) {
        self.preferences = preferences
    }

    /// Saves the configuration to the preference store.
    ///
    /// - Parameter configuration: The AI configuration to persist.
    func save(_ configuration: AIConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }
        preferences.set(jsonString, forKey: Self.storageKey)
    }

    /// Loads the configuration from the preference store.
    /// Returns `.default` if no configuration is stored or if the stored data is corrupt.
    ///
    /// - Returns: The stored AI configuration, or `.default`.
    func load() -> AIConfiguration {
        guard let jsonString = preferences.string(forKey: Self.storageKey),
              let data = jsonString.data(using: .utf8),
              let config = try? JSONDecoder().decode(AIConfiguration.self, from: data) else {
            return .default
        }
        return config
    }
}
