// Purpose: User preferences for AI capabilities (Semantic search, OCR, Apple Foundation Models mode).
// Stored in UserDefaults, keeping WI-5 authorization preferences distinct and untouched.

import Foundation

struct AIAgentCapabilityPreferences: Codable, Sendable, Equatable {
    var isSemanticSearchEnabled: Bool
    var isOCREnabled: Bool
    var foundationModelMode: AppleFoundationModelMode
    var isPCCConsentGranted: Bool

    static let `default` = AIAgentCapabilityPreferences(
        isSemanticSearchEnabled: false,
        isOCREnabled: true,
        foundationModelMode: .onDevice,
        isPCCConsentGranted: false
    )
}

actor AIAgentCapabilityPreferencesStore {
    static let shared = AIAgentCapabilityPreferencesStore()
    private let userDefaults: UserDefaults
    private let key = "vreader.ai.capabilityPreferences"
    private var cached: AIAgentCapabilityPreferences

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AIAgentCapabilityPreferences.self, from: data) {
            self.cached = decoded
        } else {
            self.cached = .default
        }
    }

    func load() -> AIAgentCapabilityPreferences {
        cached
    }

    func save(_ prefs: AIAgentCapabilityPreferences) {
        cached = prefs
        if let data = try? JSONEncoder().encode(prefs) {
            userDefaults.set(data, forKey: key)
        }
    }
}
