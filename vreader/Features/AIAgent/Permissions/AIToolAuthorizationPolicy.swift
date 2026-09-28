// Purpose: The single permission decision point for AI-agent operations. It
// combines category policy with the existing structured reading-boundary policy.

import Foundation

enum AIToolAuthorizationDecision: Equatable, Sendable {
    case allow
    case requireConfirmation(AIActionConfirmationRequest)
    case deny
}

struct AIToolAuthorizationPolicy: Sendable {
    func authorize(
        _ context: AIToolAuthorizationContext,
        preferences: AIAgentPreferences
    ) -> AIToolAuthorizationDecision {
        let persisted = preferences.decision(for: context.permissionCategory)
        if persisted == .deny {
            return .deny
        }

        // Destructive work may be denied outright, but can never be immediately
        // allowed. A persisted allow is intentionally demoted to one confirmation.
        if context.isDestructive || context.permissionCategory == .removeData {
            return .requireConfirmation(context.confirmationRequest())
        }

        switch persisted {
        case .allow:
            return .allow
        case .ask:
            return .requireConfirmation(context.confirmationRequest())
        case .deny:
            return .deny
        }
    }

    func authorizeReadAhead(
        candidate: AIDocumentChunk,
        boundary: AIReadSoFarBoundary,
        context: AIToolAuthorizationContext,
        preferences: AIAgentPreferences
    ) -> AIToolAuthorizationDecision {
        let boundaryDecision = AIReadingBoundaryPolicy(mode: preferences.readAheadMode)
            .evaluate(candidate: candidate, boundary: boundary)

        switch boundaryDecision {
        case .denied:
            return .deny

        case .allowed(let aheadOfReader):
            // Current/behind content did not cross the spoiler boundary, so the
            // read-ahead category does not apply. The caller separately enforces
            // its tool category. Whole-book permission relaxes only this boundary;
            // ahead/unknown content still honors the read-ahead category.
            guard aheadOfReader != false else { return .allow }
            return authorize(context, preferences: preferences)

        case .requiresConfirmation:
            // Ask mode is stronger than a remembered category allow: text remains
            // withheld until this specific request is approved.
            guard preferences.decision(for: context.permissionCategory) != .deny else {
                return .deny
            }
            return .requireConfirmation(
                context.confirmationRequest(sourceLocator: candidate.locator)
            )
        }
    }
}
