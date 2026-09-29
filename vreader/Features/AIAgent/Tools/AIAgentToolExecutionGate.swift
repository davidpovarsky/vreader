// Purpose: One execution-time authorization seam for every Feature #177 tool.
// Tools describe an action; this type alone evaluates WI-5 policy and broker flow.

import Foundation

enum AIConfirmationAvailability: Equatable, Sendable {
    case brokerConnected
    case unavailable
}

enum AIAgentToolAuthorizationOutcome: Equatable, Sendable {
    case allowed
    case denied
    case approvalUnavailable
    case cancelled

    var recoverableMessage: String {
        switch self {
        case .allowed:
            return ""
        case .denied:
            return "This action is not allowed by the current AI tool permissions."
        case .approvalUnavailable:
            return "Approval is required, but confirmation is not available right now."
        case .cancelled:
            return "The action was cancelled before it could run."
        }
    }
}

struct AIAgentToolExecutionGate: Sendable {
    let preferencesStore: any AIAgentPreferencesStoring
    let broker: AIActionConfirmationBroker
    let policy: AIToolAuthorizationPolicy
    let confirmationAvailability: AIConfirmationAvailability

    init(
        preferencesStore: any AIAgentPreferencesStoring = AIAgentPreferencesStore.shared,
        broker: AIActionConfirmationBroker,
        policy: AIToolAuthorizationPolicy = AIToolAuthorizationPolicy(),
        confirmationAvailability: AIConfirmationAvailability
    ) {
        self.preferencesStore = preferencesStore
        self.broker = broker
        self.policy = policy
        self.confirmationAvailability = confirmationAvailability
    }

    static func productionUnavailable(
        preferencesStore: any AIAgentPreferencesStoring = AIAgentPreferencesStore.shared
    ) -> AIAgentToolExecutionGate {
        AIAgentToolExecutionGate(
            preferencesStore: preferencesStore,
            broker: AIActionConfirmationBroker(preferencesStore: preferencesStore),
            confirmationAvailability: .unavailable
        )
    }

    func authorize(
        _ context: AIToolAuthorizationContext
    ) async -> AIAgentToolAuthorizationOutcome {
        guard !Task.isCancelled else { return .cancelled }
        let preferences = await preferencesStore.load()
        guard !Task.isCancelled else { return .cancelled }
        return await resolve(policy.authorize(context, preferences: preferences))
    }

    func authorize(
        _ contexts: [AIToolAuthorizationContext]
    ) async -> AIAgentToolAuthorizationOutcome {
        for context in contexts {
            let outcome = await authorize(context)
            guard outcome == .allowed else { return outcome }
        }
        return Task.isCancelled ? .cancelled : .allowed
    }

    func authorizeReadAhead(
        candidate: AIDocumentChunk,
        boundary: AIReadSoFarBoundary,
        context: AIToolAuthorizationContext
    ) async -> AIAgentToolAuthorizationOutcome {
        guard !Task.isCancelled else { return .cancelled }
        let preferences = await preferencesStore.load()
        guard !Task.isCancelled else { return .cancelled }
        return await resolve(policy.authorizeReadAhead(
            candidate: candidate,
            boundary: boundary,
            context: context,
            preferences: preferences
        ))
    }

    private func resolve(
        _ decision: AIToolAuthorizationDecision
    ) async -> AIAgentToolAuthorizationOutcome {
        switch decision {
        case .allow:
            return Task.isCancelled ? .cancelled : .allowed
        case .deny:
            return .denied
        case .requireConfirmation(let request):
            guard confirmationAvailability == .brokerConnected else {
                return .approvalUnavailable
            }
            let outcome = await broker.requestConfirmation(request)
            guard !Task.isCancelled else { return .cancelled }
            switch outcome {
            case .allowed: return .allowed
            case .denied: return .denied
            case .cancelled: return .cancelled
            }
        }
    }
}

enum AIAgentToolAuthorization {
    static func context(
        toolName: String,
        actionDescription: String,
        category: AIToolPermissionCategory,
        bookFingerprintKey: String? = nil,
        sourceLocator: Locator? = nil,
        metadata: [String: String] = [:]
    ) -> AIToolAuthorizationContext {
        AIToolAuthorizationContext(
            toolName: toolName,
            actionDescription: actionDescription,
            permissionCategory: category,
            metadata: metadata,
            bookFingerprintKey: bookFingerprintKey,
            sourceLocator: sourceLocator
        )
    }

    static func errorResult(
        _ outcome: AIAgentToolAuthorizationOutcome,
        maxBytes: Int
    ) -> ToolResult {
        ToolResult(
            toolUseID: "",
            content: ToolResultText.clamp(outcome.recoverableMessage, toBytes: maxBytes),
            isError: true
        )
    }
}
