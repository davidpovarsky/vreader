import Foundation
import Testing
@testable import vreader

@Suite("Feature #177 WI-5 — tool authorization policy")
struct AIToolAuthorizationPolicyTests {
    private let policy = AIToolAuthorizationPolicy()

    private func context(
        category: AIToolPermissionCategory,
        destructive: Bool = false,
        rememberEligible: Bool = true
    ) -> AIToolAuthorizationContext {
        AIToolAuthorizationContext(
            toolName: "test_tool",
            actionDescription: "Perform the test action",
            permissionCategory: category,
            isDestructive: destructive,
            rememberAllowEligible: rememberEligible
        )
    }

    private func preferences(
        _ decision: AIToolPermissionDecision,
        for category: AIToolPermissionCategory
    ) -> AIAgentPreferences {
        var value = AIAgentPreferences.default
        value.setDecision(decision, for: category)
        return value
    }

    @Test("allow permits immediately")
    func allowDecision() {
        let result = policy.authorize(
            context(category: .readCurrentBook),
            preferences: preferences(.allow, for: .readCurrentBook)
        )
        #expect(result == .allow)
    }

    @Test("ask requires confirmation")
    func askDecision() {
        let result = policy.authorize(
            context(category: .readOtherBooks),
            preferences: preferences(.ask, for: .readOtherBooks)
        )
        guard case .requireConfirmation(let request) = result else {
            Issue.record("Expected a confirmation request")
            return
        }
        #expect(request.permissionCategory == .readOtherBooks)
    }

    @Test("deny rejects immediately")
    func denyDecision() {
        let result = policy.authorize(
            context(category: .externalNetwork),
            preferences: preferences(.deny, for: .externalNetwork)
        )
        #expect(result == .deny)
    }

    @Test("destructive allow still requires confirmation")
    func destructiveAlwaysConfirms() {
        let result = policy.authorize(
            context(category: .removeData, destructive: true),
            preferences: preferences(.allow, for: .removeData)
        )
        guard case .requireConfirmation(let request) = result else {
            Issue.record("Destructive work must never be immediately allowed")
            return
        }
        #expect(request.isDestructive)
    }

    @Test("destructive confirmation cannot remember allow")
    func destructiveCannotRemember() {
        let result = policy.authorize(
            context(category: .removeData, destructive: true, rememberEligible: true),
            preferences: preferences(.allow, for: .removeData)
        )
        guard case .requireConfirmation(let request) = result else {
            Issue.record("Expected destructive confirmation")
            return
        }
        #expect(!request.rememberAllowEligible)
    }

    @Test("safe ask confirmation may remember allow")
    func safeAskMayRemember() {
        let result = policy.authorize(
            context(category: .navigateReader),
            preferences: preferences(.ask, for: .navigateReader)
        )
        guard case .requireConfirmation(let request) = result else {
            Issue.record("Expected safe confirmation")
            return
        }
        #expect(request.rememberAllowEligible)
    }

    @Test("one category cannot authorize another")
    func unrelatedCategoryDoesNotAuthorize() {
        var value = AIAgentPreferences.default
        value.setDecision(.allow, for: .readCurrentBook)
        value.setDecision(.deny, for: .readOtherBooks)

        #expect(policy.authorize(
            context(category: .readOtherBooks), preferences: value
        ) == .deny)
    }
}
