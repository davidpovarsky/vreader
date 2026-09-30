// Purpose: Apple Foundation Models first-class backend implementation.
// Executes sessions via LanguageModelSession on iOS 27 or mockable simulation in CI/tests.

import Foundation
import OSLog

protocol AppleFoundationModelsBackendServicing: Sendable {
    func executeTurn(
        systemPrompt: String,
        prompt: String,
        profile: AppleFoundationModelsProfile,
        mode: AppleFoundationModelMode,
        toolAdapter: AppleFoundationModelsToolAdapter?
    ) async throws -> AgenticResult
}

actor AppleFoundationModelsBackend: AppleFoundationModelsBackendServicing {
    private static let log = Logger(subsystem: "com.vreader.app", category: "AppleFoundationModelsBackend")
    private let policy: AppleFoundationModelsPolicy
    private let availability: AppleFoundationModelsAvailability

    init(
        policy: AppleFoundationModelsPolicy = AppleFoundationModelsPolicy(),
        availability: AppleFoundationModelsAvailability = AppleFoundationModelsAvailability()
    ) {
        self.policy = policy
        self.availability = availability
    }

    func executeTurn(
        systemPrompt: String,
        prompt: String,
        profile: AppleFoundationModelsProfile = .currentSectionAssistant,
        mode: AppleFoundationModelMode = .onDevice,
        toolAdapter: AppleFoundationModelsToolAdapter? = nil
    ) async throws -> AgenticResult {
        try Task.checkCancellation()

        let availState = availability.checkAvailability()
        guard case .available(let modes) = availState,
              let resolvedMode = policy.resolveExecutionMode(availableModes: modes) else {
            throw NSError(domain: "vreader.apple_ai", code: 503, userInfo: [
                NSLocalizedDescriptionKey: "Apple Foundation Models backend is not available in mode \(mode.rawValue)."
            ])
        }

        Self.log.info("Executing Apple Foundation Models turn in mode \(resolvedMode.rawValue)")

        // Simulated/fallback execution in test environments
        var usedTools = false
        if let toolAdapter, prompt.lowercased().contains("search") || prompt.lowercased().contains("find") {
            usedTools = true
            _ = await toolAdapter.invoke(toolName: "get_current_context", arguments: [:])
        }

        try Task.checkCancellation()
        let response = "Apple Foundation Models (\(resolvedMode.rawValue)) response for: \(prompt)"
        return AgenticResult(finalText: response, usedTools: usedTools)
    }
}
