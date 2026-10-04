// Purpose: Apple Foundation Models first-class backend implementation.
// Executes sessions via real LanguageModelSession on iOS 26+ / iOS 27 with availability,
// policy enforcement, multi-turn session persistence, and native tool execution.

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
        policy: AppleFoundationModelsPolicy?,
        toolAdapter: AppleFoundationModelsToolAdapter?
    ) async throws -> AgenticResult
}

extension AppleFoundationModelsBackendServicing {
    func executeTurn(
        systemPrompt: String,
        prompt: String,
        profile: AppleFoundationModelsProfile = .currentSectionAssistant,
        mode: AppleFoundationModelMode = .onDevice,
        toolAdapter: AppleFoundationModelsToolAdapter? = nil
    ) async throws -> AgenticResult {
        try await executeTurn(
            systemPrompt: systemPrompt,
            prompt: prompt,
            profile: profile,
            mode: mode,
            policy: nil,
            toolAdapter: toolAdapter
        )
    }
}

actor AppleFoundationModelsBackend: AppleFoundationModelsBackendServicing {
    private static let log = Logger(subsystem: "com.vreader.app", category: "AppleFoundationModelsBackend")
    private let policy: AppleFoundationModelsPolicy
    private let availability: AppleFoundationModelsAvailability

#if canImport(FoundationModels)
    private var activeSessions: [String: LanguageModelSession] = [:]
#endif

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
        policy explicitPolicy: AppleFoundationModelsPolicy? = nil,
        toolAdapter: AppleFoundationModelsToolAdapter? = nil
    ) async throws -> AgenticResult {
        try Task.checkCancellation()

        let effectivePolicy = explicitPolicy ?? self.policy
        let availState = availability.checkAvailability()
        guard availState.isAvailable,
              let resolvedMode = effectivePolicy.resolveExecutionMode(availableModes: [.onDevice, .privateCloudCompute, .automatic]) else {
            throw NSError(domain: "vreader.apple_ai", code: 503, userInfo: [
                NSLocalizedDescriptionKey: "Apple Foundation Models backend is not available in mode \(mode.rawValue)."
            ])
        }

        Self.log.info("Executing Apple Foundation Models turn in mode \(resolvedMode.rawValue)")

#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let sessionKey = "\(profile.identifier):\(systemPrompt.hashValue)"
            let session: LanguageModelSession
            if let existing = activeSessions[sessionKey] {
                session = existing
            } else {
                let newSession = LanguageModelSession(instructions: systemPrompt)
                activeSessions[sessionKey] = newSession
                session = newSession
            }

            var usedTools = false
            var currentPrompt = prompt
            var finalText = ""

            let maxIterations = (toolAdapter != nil && !toolAdapter!.registry.isEmpty) ? 4 : 1
            for _ in 0..<maxIterations {
                try Task.checkCancellation()
                let response = try await session.respond(to: currentPrompt)
                finalText = response.content

                guard let adapter = toolAdapter, !adapter.registry.isEmpty else {
                    break
                }

                if let toolCall = parseToolCall(response.content, registry: adapter.registry) {
                    usedTools = true
                    try Task.checkCancellation()
                    let result = await adapter.invoke(
                        toolName: toolCall.name,
                        input: toolCall.input,
                        callID: toolCall.id
                    )
                    currentPrompt = "Tool result for \(toolCall.name):\n\(result.content)"
                } else {
                    break
                }
            }

            return AgenticResult(
                finalText: finalText,
                usedTools: usedTools,
                citations: [],
                sourceProvenances: []
            )
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

    private nonisolated func parseToolCall(
        _ content: String,
        registry: AIToolRegistry
    ) -> (id: String, name: String, input: JSONValue)? {
        // Match JSON object indicating a tool call: {"tool": "...", "arguments": {...}}
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let toolName = (json["tool"] as? String) ?? (json["name"] as? String) ?? ""
        guard !toolName.isEmpty, registry.hasTool(named: toolName) else {
            return nil
        }
        let args = (json["arguments"] as? [String: Any]) ?? (json["parameters"] as? [String: Any]) ?? [:]
        let callID = (json["id"] as? String) ?? UUID().uuidString
        return (id: callID, name: toolName, input: JSONValue(foundation: args))
    }
}
