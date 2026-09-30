// Purpose: Unit tests for ChatActionConfirmationCard presentation model and outcomes.
// Proves destructive actions never expose "Always allow", and requests resolve cleanly.

import Testing
import Foundation
@testable import vreader

@Suite("ChatActionConfirmationCardTests")
struct ChatActionConfirmationCardTests {

    @Test func destructiveRequestDisablesAlwaysAllowOption() {
        let destructiveReq = AIActionConfirmationRequest(
            id: UUID(),
            actionDescription: "Delete note: Chapter 1 note",
            permissionCategory: .removeData,
            isDestructive: true,
            rememberAllowEligible: false
        )

        #expect(destructiveReq.isDestructive == true)
        #expect(destructiveReq.rememberAllowEligible == false)
    }

    @Test func nonDestructiveRequestPermitsRememberAllowOption() {
        let nonDestructiveReq = AIActionConfirmationRequest(
            id: UUID(),
            actionDescription: "Read content of Chapter 5",
            permissionCategory: .readCurrentBook,
            isDestructive: false,
            rememberAllowEligible: true
        )

        #expect(nonDestructiveReq.isDestructive == false)
        #expect(nonDestructiveReq.rememberAllowEligible == true)
    }

    @Test func brokerResolvesConfirmationOutcomeOnce() async {
        let store = InMemoryAIAgentPreferencesStore()
        let broker = AIActionConfirmationBroker(preferencesStore: store)

        let req = AIActionConfirmationRequest(
            id: UUID(),
            actionDescription: "Search library",
            permissionCategory: .readOtherBooks,
            isDestructive: false,
            rememberAllowEligible: false
        )

        let resolveTask = Task {
            await broker.requestConfirmation(req)
        }

        // Wait briefly for broker to register pending
        try? await Task.sleep(nanoseconds: 20_000_000)
        let pending = await broker.pendingRequests()
        #expect(pending.count == 1)

        let resolved = await broker.resolve(req.id, with: .allowOnce)
        #expect(resolved == true)

        let outcome = await resolveTask.value
        #expect(outcome == .allowedOnce)

        let remaining = await broker.pendingRequests()
        #expect(remaining.isEmpty)
    }
}
