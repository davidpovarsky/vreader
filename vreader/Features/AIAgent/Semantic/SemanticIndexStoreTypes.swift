// Purpose: Supporting types and error definitions for SemanticIndexStore.
// Kept separate to ensure file sizes remain strictly under 300 lines.

import Foundation

enum SemanticIndexStoreError: Error, LocalizedError, Sendable, Equatable {
    case dimensionMismatch(expected: Int, actual: Int)
    case indexCorrupted
    case fileOperationFailed(String)
    case indexUnavailable
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .dimensionMismatch(let expected, let actual):
            return "Vector dimension mismatch: expected \(expected), got \(actual)."
        case .indexCorrupted:
            return "Vector index file is corrupted or incompatible."
        case .fileOperationFailed(let msg):
            return "Vector index file operation failed: \(msg)"
        case .indexUnavailable:
            return "USearch vector index engine is unavailable."
        case .operationFailed(let msg):
            return "Vector index operation failed: \(msg)"
        }
    }
}

struct SemanticIndexStoreResult: Sendable, Equatable {
    let key: UInt64
    let chunkID: String
    let distance: Float
    let similarity: Float
}

struct SemanticIndexInsertItem: Sendable {
    let chunkID: String
    let bookFingerprintKey: String
    let vector: [Float]

    init(chunkID: String, bookFingerprintKey: String, vector: [Float]) {
        self.chunkID = chunkID
        self.bookFingerprintKey = bookFingerprintKey
        self.vector = vector
    }

    init(key: UInt64 = 0, chunkID: String, bookFingerprintKey: String, vector: [Float]) {
        self.chunkID = chunkID
        self.bookFingerprintKey = bookFingerprintKey
        self.vector = vector
    }
}
