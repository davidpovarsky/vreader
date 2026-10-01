// Purpose: Apple Foundation Models first-class backend implementation.
// Executes sessions via real LanguageModelSession on iOS 26+ / iOS 27 with availability and policy enforcement.

import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

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
        guard availState.isAvailable,
              let resolvedMode = policy.resolveExecutionMode(availableModes: [.onDevice, .privateCloudCompute, .automatic]) else {
            throw NSError(domain: "vreader.apple_ai", code: 503, userInfo: [
                NSLocalizedDescriptionKey: "Apple Foundation Models backend is not available in mode \(mode.rawValue)."
            ])
        }

        Self.log.info("Executing Apple Foundation Models turn in mode \(resolvedMode.rawValue)")

#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(instructions: systemPrompt)
            let response = try await session.respond(to: prompt)
            return AgenticResult(finalText: response.content, usedTools: false)
        } else {
            throw NSError(domain: "vreader.apple_ai", code: 503, userInfo: [
                NSLocalizedDescriptionKey: "Apple Foundation Models requires iOS 26+."
            ])
        }
#else
        throw NSError(domain: "vreader.apple_ai", code: 503, userInfo: [
            NSLocalizedDescriptionKey: "Apple Foundation Models framework unavailable on this platform."
        ])
#endif
    }
}
