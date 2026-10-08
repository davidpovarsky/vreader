// Purpose: Apple Foundation Models first-class backend implementation.
// Executes sessions via real LanguageModelSession on iOS 26+ / iOS 27 with availability,
// policy enforcement, multi-turn session persistence, and native tool execution.

import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

protocol AppleLanguageModelSessionProtocol: Sendable {
    func respond(to prompt: String) async throws -> String
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
final class RealAppleLanguageModelSession: AppleLanguageModelSessionProtocol {
    private let session: LanguageModelSession

    init(instructions: String, tools: [any Tool]) {
        self.session = LanguageModelSession(model: SystemLanguageModel.default, tools: tools, instructions: instructions)
    }

    func respond(to prompt: String) async throws -> String {
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
#endif

protocol AppleFoundationModelsBackendServicing: Sendable {
    func executeTurn(
        systemPrompt: String,
        prompt: String,
        profile: AppleFoundationModelsProfile,
        mode: AppleFoundationModelMode,
        policy: AppleFoundationModelsPolicy?,
        toolAdapter: AppleFoundationModelsToolAdapter?,
        documentSessionID: AIDocumentSessionID?,
        turnID: String
    ) async throws -> AgenticResult
}

extension AppleFoundationModelsBackendServicing {
    func executeTurn(
        systemPrompt: String,
        prompt: String,
        profile: AppleFoundationModelsProfile = .currentSectionAssistant,
        mode: AppleFoundationModelMode = .onDevice,
        policy: AppleFoundationModelsPolicy? = nil,
        toolAdapter: AppleFoundationModelsToolAdapter? = nil,
        documentSessionID: AIDocumentSessionID? = nil,
        turnID: String = UUID().uuidString
    ) async throws -> AgenticResult {
        try await executeTurn(
            systemPrompt: systemPrompt,
            prompt: prompt,
            profile: profile,
            mode: mode,
            policy: policy,
            toolAdapter: toolAdapter,
            documentSessionID: documentSessionID,
            turnID: turnID
        )
    }

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
            toolAdapter: toolAdapter,
            documentSessionID: nil,
            turnID: UUID().uuidString
        )
    }
}

actor AppleFoundationModelsBackend: AppleFoundationModelsBackendServicing {
    private static let log = Logger(subsystem: "com.vreader.app", category: "AppleFoundationModelsBackend")
    private let policy: AppleFoundationModelsPolicy
    private let availability: AppleFoundationModelsAvailability

    typealias SessionFactory = @Sendable (String, [Any]) throws -> any AppleLanguageModelSessionProtocol
    private let sessionFactory: SessionFactory?
    private var activeSessions: [String: any AppleLanguageModelSessionProtocol] = [:]

    init(
        policy: AppleFoundationModelsPolicy = AppleFoundationModelsPolicy(),
        availability: AppleFoundationModelsAvailability = AppleFoundationModelsAvailability(),
        sessionFactory: SessionFactory? = nil
    ) {
        self.policy = policy
        self.availability = availability
        self.sessionFactory = sessionFactory
    }

    func executeTurn(
        systemPrompt: String,
        prompt: String,
        profile: AppleFoundationModelsProfile = .currentSectionAssistant,
        mode: AppleFoundationModelMode = .onDevice,
        policy explicitPolicy: AppleFoundationModelsPolicy? = nil,
        toolAdapter: AppleFoundationModelsToolAdapter? = nil,
        documentSessionID: AIDocumentSessionID? = nil,
        turnID: String = UUID().uuidString
    ) async throws -> AgenticResult {
        try Task.checkCancellation()

        let effectivePolicy = explicitPolicy ?? self.policy
        let availState = availability.checkAvailability()
        guard availState.isAvailable,
              let resolvedMode = effectivePolicy.resolveExecutionMode(availableModes: [.onDevice]) else {
            throw NSError(domain: "vreader.apple_ai", code: 503, userInfo: [
                NSLocalizedDescriptionKey: "Apple Foundation Models backend is not available in mode \(mode.rawValue)."
            ])
        }

        Self.log.info("Executing Apple Foundation Models turn in mode \(resolvedMode.rawValue)")

        let sessionKey: String
        if let docID = documentSessionID {
            sessionKey = "\(docID.fingerprintKey):\(docID.readerToken.uuidString):\(profile.identifier)"
        } else {
            sessionKey = "transient:\(UUID().uuidString):\(profile.identifier)"
        }

        let tappingSink = ProvenanceTapSink(downstream: toolAdapter?.eventSink)

        let session: any AppleLanguageModelSessionProtocol
        if let existing = activeSessions[sessionKey] {
            session = existing
        } else {
            let newSession: any AppleLanguageModelSessionProtocol
            if let factory = self.sessionFactory {
                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, *) {
                    let nativeTools = toolAdapter?.makeNativeTools(
                        turnID: turnID,
                        documentSessionID: documentSessionID,
                        sink: tappingSink
                    ) ?? []
                    newSession = try factory(systemPrompt, nativeTools)
                } else {
                    newSession = try factory(systemPrompt, [])
                }
                #else
                newSession = try factory(systemPrompt, [])
                #endif
            } else {
                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, *) {
                    let nativeTools = toolAdapter?.makeNativeTools(
                        turnID: turnID,
                        documentSessionID: documentSessionID,
                        sink: tappingSink
                    ) ?? []
                    newSession = RealAppleLanguageModelSession(instructions: systemPrompt, tools: nativeTools)
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
            activeSessions[sessionKey] = newSession
            session = newSession
        }

        try Task.checkCancellation()
        let responseText = try await session.respond(to: prompt)
        try Task.checkCancellation()

        let collectedSources = await tappingSink.collectedSources()
        let uniqueSources = Self.deduplicateSources(collectedSources)
        let citations = uniqueSources.compactMap { $0.toChatCitation() }
        let usedTools = (toolAdapter != nil && !uniqueSources.isEmpty)

        return AgenticResult(
            finalText: responseText,
            usedTools: usedTools,
            citations: citations,
            sourceProvenances: uniqueSources
        )
    }

    private static func deduplicateSources(_ sources: [AISourceProvenance]) -> [AISourceProvenance] {
        var seen = Set<String>()
        var result: [AISourceProvenance] = []
        for src in sources {
            let key = "\(src.bookFingerprintKey)|\(src.href ?? "")|\(src.pageIndex ?? -1)|\(src.snippet)"
            if !seen.contains(src.id) && !seen.contains(key) {
                seen.insert(src.id)
                seen.insert(key)
                result.append(src)
            }
        }
        return result
    }

    /// Preserves bounded multi-turn conversation transcripts without persisting framework objects.
    final class SessionTranscript: @unchecked Sendable {
        struct Turn: Sendable {
            let role: String
            let text: String
        }

        let sessionID: String
        private(set) var turns: [Turn] = []

        init(sessionID: String) {
            self.sessionID = sessionID
        }

        func append(role: String, text: String) {
            turns.append(Turn(role: role, text: text))
        }
    }
}
