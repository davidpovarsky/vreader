// Purpose: Bounded idempotency tracker for tool mutations.
// Prevents duplicate persistence side-effects across retries or multiple confirmation resolutions.

import Foundation

struct AIToolMutationOutcome: Sendable, Equatable {
    let recordID: String
    let summary: String
}

actor AIToolMutationIdempotency {
    static let shared = AIToolMutationIdempotency()

    private var completedOperations: [String: String] = [:]
    private var completedOutcomes: [String: AIToolMutationOutcome] = [:]
    private let maxEntries: Int

    init(maxEntries: Int = 100) {
        self.maxEntries = max(10, maxEntries)
    }

    /// Checks if a mutation with this idempotency key has already completed.
    func isCompleted(idempotencyKey: String) -> Bool {
        completedOutcomes[idempotencyKey] != nil || completedOperations[idempotencyKey] != nil
    }

    /// Records completed outcome for an idempotency key.
    func recordCompleted(idempotencyKey: String, recordID: String, summary: String) {
        if completedOutcomes.count >= maxEntries {
            completedOutcomes.remove(at: completedOutcomes.startIndex)
        }
        let outcome = AIToolMutationOutcome(recordID: recordID, summary: summary)
        completedOutcomes[idempotencyKey] = outcome
        record(operationID: idempotencyKey, result: summary)
    }

    /// Returns the outcome of a completed mutation, if any.
    func outcome(idempotencyKey: String) -> AIToolMutationOutcome? {
        completedOutcomes[idempotencyKey]
    }

    /// Checks if an operation with this ID has already succeeded. Returns the stored result if so.
    func result(for operationID: String) -> String? {
        completedOperations[operationID]
    }

    /// Records successful execution of a mutation operation.
    func record(operationID: String, result: String) {
        if completedOperations.count >= maxEntries {
            completedOperations.remove(at: completedOperations.startIndex)
        }
        completedOperations[operationID] = result
    }

    func clear() {
        completedOperations.removeAll()
        completedOutcomes.removeAll()
    }
}
