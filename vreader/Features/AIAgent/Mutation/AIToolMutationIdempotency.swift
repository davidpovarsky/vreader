// Purpose: Bounded idempotency tracker for tool mutations.
// Prevents duplicate persistence side-effects across retries or multiple confirmation resolutions.

import Foundation

actor AIToolMutationIdempotency {
    static let shared = AIToolMutationIdempotency()

    private var completedOperations: [String: String] = [:]
    private let maxEntries: Int

    init(maxEntries: Int = 100) {
        self.maxEntries = max(10, maxEntries)
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
    }
}
