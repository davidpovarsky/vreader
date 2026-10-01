// Purpose: User preferences for AI capabilities (Semantic search, OCR, Apple Foundation Models mode, backend choice).
// Stored in UserDefaults, keeping WI-5 authorization preferences distinct and untouched.

import Foundation

extension Notification.Name {
    static let aiAgentConfigurationDidChange = Notification.Name("vreader.aiAgent.configurationDidChange")
}

final class AIAgentCapabilityPreferences: Codable, @unchecked Sendable, Equatable {
    var isSemanticSearchEnabled: Bool
    var isOCREnabled: Bool
    var foundationModelMode: AppleFoundationModelMode
    var isPCCConsentGranted: Bool
    var backendChoice: AIAgentBackendChoice

    init(
        isSemanticSearchEnabled: Bool = false,
        isOCREnabled: Bool = true,
        foundationModelMode: AppleFoundationModelMode = .onDevice,
        isPCCConsentGranted: Bool = false,
        backendChoice: AIAgentBackendChoice = .cloudProvider
    ) {
        self.isSemanticSearchEnabled = isSemanticSearchEnabled
        self.isOCREnabled = isOCREnabled
        self.foundationModelMode = foundationModelMode
        self.isPCCConsentGranted = isPCCConsentGranted
        self.backendChoice = backendChoice
    }

    static var `default`: AIAgentCapabilityPreferences {
        AIAgentCapabilityPreferences(
            isSemanticSearchEnabled: false,
            isOCREnabled: true,
            foundationModelMode: .onDevice,
            isPCCConsentGranted: false,
            backendChoice: .cloudProvider
        )
    }

    private enum CodingKeys: String, CodingKey {
        case isSemanticSearchEnabled
        case isOCREnabled
        case foundationModelMode
        case isPCCConsentGranted
        case backendChoice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isSemanticSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSemanticSearchEnabled) ?? false
        self.isOCREnabled = try container.decodeIfPresent(Bool.self, forKey: .isOCREnabled) ?? true
        self.foundationModelMode = try container.decodeIfPresent(AppleFoundationModelMode.self, forKey: .foundationModelMode) ?? .onDevice
        self.isPCCConsentGranted = try container.decodeIfPresent(Bool.self, forKey: .isPCCConsentGranted) ?? false
        self.backendChoice = try container.decodeIfPresent(AIAgentBackendChoice.self, forKey: .backendChoice) ?? .cloudProvider
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isSemanticSearchEnabled, forKey: .isSemanticSearchEnabled)
        try container.encode(isOCREnabled, forKey: .isOCREnabled)
        try container.encode(foundationModelMode, forKey: .foundationModelMode)
        try container.encode(isPCCConsentGranted, forKey: .isPCCConsentGranted)
        try container.encode(backendChoice, forKey: .backendChoice)
    }

    static func == (lhs: AIAgentCapabilityPreferences, rhs: AIAgentCapabilityPreferences) -> Bool {
        lhs.isSemanticSearchEnabled == rhs.isSemanticSearchEnabled &&
        lhs.isOCREnabled == rhs.isOCREnabled &&
        lhs.foundationModelMode == rhs.foundationModelMode &&
        lhs.isPCCConsentGranted == rhs.isPCCConsentGranted &&
        lhs.backendChoice == rhs.backendChoice
    }
}

actor AIAgentCapabilityPreferencesStore {
    static let shared = AIAgentCapabilityPreferencesStore()
    private let userDefaults: UserDefaults
    private let key = "vreader.ai.capabilityPreferences"
    private var cached: AIAgentCapabilityPreferences

    nonisolated static func currentBackendChoice(userDefaults: UserDefaults = .standard) -> AIAgentBackendChoice {
        guard let data = userDefaults.data(forKey: "vreader.ai.capabilityPreferences"),
              let decoded = try? JSONDecoder().decode(AIAgentCapabilityPreferences.self, from: data) else {
            return .cloudProvider
        }
        return decoded.backendChoice
    }

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
        NotificationCenter.default.post(name: .aiAgentConfigurationDidChange, object: nil)
    }
}
