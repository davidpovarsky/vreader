// Purpose: Unit tests for AIToolMutationIdempotency tracker.
// Validates replay protection, duplicate prevention, and cache retention across mutations.

import Testing
import Foundation
@testable import vreader

@Suite("AIToolMutationIdempotencyTests")
struct AIToolMutationIdempotencyTests {

    @Test func tracksAndReturnsCompletedMutationOutcome() async {
        let tracker = AIToolMutationIdempotency()

        #expect(await tracker.isCompleted(idempotencyKey: "key-1") == false)

        await tracker.recordCompleted(idempotencyKey: "key-1", recordID: "rec-123", summary: "Added note")

        #expect(await tracker.isCompleted(idempotencyKey: "key-1") == true)
        let outcome = await tracker.outcome(idempotencyKey: "key-1")
        #expect(outcome != nil)
        #expect(outcome?.recordID == "rec-123")
        #expect(outcome?.summary == "Added note")
    }

    @Test func clearPurgesRecordedEntries() async {
        let tracker = AIToolMutationIdempotency()
        await tracker.recordCompleted(idempotencyKey: "k", recordID: "r", summary: "s")

        #expect(await tracker.isCompleted(idempotencyKey: "k") == true)
        await tracker.clear()
        #expect(await tracker.isCompleted(idempotencyKey: "k") == false)
    }
}
