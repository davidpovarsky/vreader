// Purpose: Actor-isolated lightweight persistence for AI-agent preferences.
// The injected PreferenceStoring backend keeps tests isolated from app defaults.

import Foundation

protocol AIAgentPreferencesStoring: Sendable {
    func load() async -> AIAgentPreferences
    func setDecision(
        _ decision: AIToolPermissionDecision,
        for category: AIToolPermissionCategory
    ) async
    func setReadAheadMode(_ mode: AIReadAheadMode) async
}

actor AIAgentPreferencesStore: AIAgentPreferencesStoring {
    static let shared = AIAgentPreferencesStore()
    static let defaultStorageKey = "ai.agent.preferences.v1"

    private let preferences: any PreferenceStoring
    private let storageKey: String

    init(
        preferences: any PreferenceStoring = UserDefaultsPreferenceStore(),
        storageKey: String = AIAgentPreferencesStore.defaultStorageKey
    ) {
        self.preferences = preferences
        self.storageKey = storageKey
    }

    func load() -> AIAgentPreferences {
        guard let raw = preferences.string(forKey: storageKey),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AIAgentPreferences.self, from: data) else {
            return .default
        }
        return decoded
    }

    func setDecision(
        _ decision: AIToolPermissionDecision,
        for category: AIToolPermissionCategory
    ) {
        var value = load()
        value.setDecision(decision, for: category)
        persist(value)
    }

    func setReadAheadMode(_ mode: AIReadAheadMode) {
        var value = load()
        value.setReadAheadMode(mode)
        persist(value)
    }

    private func persist(_ value: AIAgentPreferences) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        preferences.set(raw, forKey: storageKey)
    }
}
