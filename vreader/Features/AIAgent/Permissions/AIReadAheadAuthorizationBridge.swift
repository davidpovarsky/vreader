// Purpose: Release a structured candidate only after the central boundary and
// permission policies allow it. Confirmation requests never carry candidate text.

import Foundation

struct AIReadAheadAuthorizationBridge: Sendable {
    let preferencesStore: any AIAgentPreferencesStoring
    let broker: AIActionConfirmationBroker
    let policy: AIToolAuthorizationPolicy

    init(
        preferencesStore: any AIAgentPreferencesStoring = AIAgentPreferencesStore.shared,
        broker: AIActionConfirmationBroker,
        policy: AIToolAuthorizationPolicy = AIToolAuthorizationPolicy()
    ) {
        self.preferencesStore = preferencesStore
        self.broker = broker
        self.policy = policy
    }

    func authorizedCandidate(
        _ candidate: AIDocumentChunk,
        boundary: AIReadSoFarBoundary,
        context: AIToolAuthorizationContext
    ) async -> AIDocumentChunk? {
        let preferences = await preferencesStore.load()
        switch policy.authorizeReadAhead(
            candidate: candidate,
            boundary: boundary,
            context: context,
            preferences: preferences
        ) {
        case .allow:
            return candidate
        case .deny:
            return nil
        case .requireConfirmation(let request):
            let outcome = await broker.requestConfirmation(request)
            guard outcome == .allowed, !Task.isCancelled else { return nil }
            return candidate
        }
    }
}
