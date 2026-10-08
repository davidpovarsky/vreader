// Purpose: Focused test suite proving exact-session confirmation isolation.
// Validates that two readers reading the same book (or different books) never cross-receive
// confirmation cards, and decisions (allow, deny, cancel) affect only the issuing session.

import Testing
import Foundation
@testable import vreader

@Suite("AIExactSessionConfirmationIsolationTests")
struct AIExactSessionConfirmationIsolationTests {

    @Test func sameBookTwoTokensIsolatesConfirmationRequests() async {
        let broker = AIActionConfirmationBroker()

        let tokenA = UUID()
        let tokenB = UUID()
        let sessionA = AIDocumentSessionID(fingerprintKey: "book-fp-same", readerToken: tokenA)
        let sessionB = AIDocumentSessionID(fingerprintKey: "book-fp-same", readerToken: tokenB)

        let reqA = AIActionConfirmationRequest(
            toolName: "delete_note",
            actionDescription: "Delete note in Reader A",
            permissionCategory: .removeData,
            readerSessionID: sessionA
        )
        let reqB = AIActionConfirmationRequest(
            toolName: "delete_note",
            actionDescription: "Delete note in Reader B",
            permissionCategory: .removeData,
            readerSessionID: sessionB
        )

        // Initial pending queues are empty
        #expect(await broker.pendingRequests(for: sessionA).isEmpty)
        #expect(await broker.pendingRequests(for: sessionB).isEmpty)

        // Request A in background
        let taskA = Task { await broker.requestConfirmation(reqA) }

        // Wait until broker has request A
        for _ in 0..<20 {
            if (await broker.pendingRequests(for: sessionA).count) == 1 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // 1. Request created by A appears only in A; B receives nothing
        let pendingA = await broker.pendingRequests(for: sessionA)
        let pendingB = await broker.pendingRequests(for: sessionB)
        #expect(pendingA.count == 1)
        #expect(pendingA.first?.id == reqA.id)
        #expect(pendingB.isEmpty)

        // Request B in background
        let taskB = Task { await broker.requestConfirmation(reqB) }
        for _ in 0..<20 {
            if (await broker.pendingRequests(for: sessionB).count) == 1 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect((await broker.pendingRequests(for: sessionA)).count == 1)
        #expect((await broker.pendingRequests(for: sessionB)).count == 1)

        // 2. Allow Once in A resumes only A
        await broker.respond(to: reqA.id, decision: .allowOnce)
        let decisionA = await taskA.value
        #expect(decisionA == .allowOnce)

        // B is still pending
        #expect((await broker.pendingRequests(for: sessionA)).isEmpty)
        #expect((await broker.pendingRequests(for: sessionB)).count == 1)

        // 3. Deny in B affects only B
        await broker.respond(to: reqB.id, decision: .deny)
        let decisionB = await taskB.value
        #expect(decisionB == .deny)
        #expect((await broker.pendingRequests(for: sessionB)).isEmpty)
    }

    @Test func sessionCancellationCleansOnlyTargetSessionPendingRequests() async {
        let broker = AIActionConfirmationBroker()

        let sessionA = AIDocumentSessionID(fingerprintKey: "book-1", readerToken: UUID())
        let sessionB = AIDocumentSessionID(fingerprintKey: "book-2", readerToken: UUID())

        let reqA = AIActionConfirmationRequest(
            toolName: "modify_text",
            actionDescription: "Modify A",
            permissionCategory: .modifyData,
            readerSessionID: sessionA
        )
        let reqB = AIActionConfirmationRequest(
            toolName: "modify_text",
            actionDescription: "Modify B",
            permissionCategory: .modifyData,
            readerSessionID: sessionB
        )

        let taskA = Task { await broker.requestConfirmation(reqA) }
        let taskB = Task { await broker.requestConfirmation(reqB) }

        for _ in 0..<20 {
            if (await broker.pendingRequests(for: sessionA).count) == 1 &&
               (await broker.pendingRequests(for: sessionB).count) == 1 {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // Cancel Session A
        await broker.cancelSession(sessionA)

        // Pending A is now empty and taskA gets denied
        #expect((await broker.pendingRequests(for: sessionA)).isEmpty)
        let decisionA = await taskA.value
        #expect(decisionA == .deny)

        // Session B remains intact
        #expect((await broker.pendingRequests(for: sessionB)).count == 1)
        await broker.respond(to: reqB.id, decision: .allowAlways)
        let decisionB = await taskB.value
        #expect(decisionB == .allowAlways)
    }
}
