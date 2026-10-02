// Purpose: AIAgent turn execution abstraction and router supporting cloud providers and Apple Foundation Models.
// Enables seamless routing without modifying existing provider transport layers.

import Foundation

enum AIAgentBackendChoice: String, Sendable, Codable, CaseIterable {
    case cloudProvider = "cloudProvider"
    case appleFoundationModels = "appleFoundationModels"

    var displayName: String {
        switch self {
        case .cloudProvider: return "Configured Provider"
        case .appleFoundationModels: return "Apple Foundation Models"
        }
    }
}

protocol AIAgentTurnExecuting: Sendable {
    func executeTurn(
        prompt: String,
        systemPrompt: String,
        contextText: String?,
        registry: AIToolRegistry,
        documentSessionID: AIDocumentSessionID?,
        turnID: String
    ) async throws -> AgenticResult
}

final class CloudProviderTurnExecutor: AIAgentTurnExecuting {
    private let aiService: AIService
    private let driver: AgenticChatDriver

    init(aiService: AIService, driver: AgenticChatDriver = AgenticChatDriver()) {
        self.aiService = aiService
        self.driver = driver
    }

    func executeTurn(
        prompt: String,
        systemPrompt: String,
        contextText: String?,
        registry: AIToolRegistry,
        documentSessionID: AIDocumentSessionID?,
        turnID: String
    ) async throws -> AgenticResult {
        let (config, _) = try await aiService.resolveToolProvider()
        var history: [ToolTurnMessage] = [ToolTurnMessage(role: .user, content: [.text(prompt)])]
        if let contextText, let prelude = AIChatHistoryMapper.contextPrelude(bookContext: contextText) {
            history.insert(prelude, at: 0)
        }
        return try await driver.run(
            systemPrompt: systemPrompt,
            history: history,
            registry: registry,
            provider: AIServiceToolUseAdapter(service: aiService, config: config),
            maxTokens: config.maxTokens,
            readerSessionID: documentSessionID,
            turnID: turnID
        )
    }
}

final class AppleFoundationModelsTurnExecutor: AIAgentTurnExecuting {
    private let backend: any AppleFoundationModelsBackendServicing
    private let executionGate: AIAgentToolExecutionGate
    private let capabilityStore: AIAgentCapabilityPreferencesStore

    init(
        backend: any AppleFoundationModelsBackendServicing = AppleFoundationModelsBackend(),
        executionGate: AIAgentToolExecutionGate,
        capabilityStore: AIAgentCapabilityPreferencesStore = .shared
    ) {
        self.backend = backend
        self.executionGate = executionGate
        self.capabilityStore = capabilityStore
    }

    func executeTurn(
        prompt: String,
        systemPrompt: String,
        contextText: String?,
        registry: AIToolRegistry,
        documentSessionID: AIDocumentSessionID?,
        turnID: String
    ) async throws -> AgenticResult {
        let toolAdapter = AppleFoundationModelsToolAdapter(
            registry: registry,
            executionGate: executionGate
        )
        let capabilities = await capabilityStore.load()
        let policy = AppleFoundationModelsPolicy(
            mode: capabilities.foundationModelMode,
            userConsentedToPCC: capabilities.isPCCConsentGranted
        )
        let combinedSystem = [systemPrompt, contextText].compactMap { $0 }.joined(separator: "\n\n")
        return try await backend.executeTurn(
            systemPrompt: combinedSystem,
            prompt: prompt,
            profile: .currentSectionAssistant,
            mode: capabilities.foundationModelMode,
            policy: policy,
            toolAdapter: toolAdapter
        )
    }
}

final class AIAgentTurnRouter: AIAgentTurnExecuting {
    private let cloudExecutor: AIAgentTurnExecuting
    private let appleExecutor: AIAgentTurnExecuting
    private let backendChoice: @Sendable () -> AIAgentBackendChoice

    init(
        cloudExecutor: AIAgentTurnExecuting,
        appleExecutor: AIAgentTurnExecuting,
        backendChoice: @escaping @Sendable () -> AIAgentBackendChoice = { .cloudProvider }
    ) {
        self.cloudExecutor = cloudExecutor
        self.appleExecutor = appleExecutor
        self.backendChoice = backendChoice
    }

    func executeTurn(
        prompt: String,
        systemPrompt: String,
        contextText: String?,
        registry: AIToolRegistry,
        documentSessionID: AIDocumentSessionID?,
        turnID: String
    ) async throws -> AgenticResult {
        switch backendChoice() {
        case .cloudProvider:
            return try await cloudExecutor.executeTurn(
                prompt: prompt,
                systemPrompt: systemPrompt,
                contextText: contextText,
                registry: registry,
                documentSessionID: documentSessionID,
                turnID: turnID
            )
        case .appleFoundationModels:
            return try await appleExecutor.executeTurn(
                prompt: prompt,
                systemPrompt: systemPrompt,
                contextText: contextText,
                registry: registry,
                documentSessionID: documentSessionID,
                turnID: turnID
            )
        }
    }
}
