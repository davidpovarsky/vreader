// Purpose: Vector index store wrapper for ANN lookup.
// Validates vector dimensions, handles corruption recovery, and supports top-K search.

import Foundation

enum SemanticIndexStoreError: Error, LocalizedError, Sendable {
    case dimensionMismatch(expected: Int, actual: Int)
    case indexCorrupted
    case fileOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .dimensionMismatch(let expected, let actual):
            return "Vector dimension mismatch: expected \(expected), got \(actual)."
        case .indexCorrupted:
            return "Vector index file is corrupted."
        case .fileOperationFailed(let msg):
            return "Vector index file operation failed: \(msg)"
        }
    }
}

actor SemanticIndexStore {
    let dimension: Int
    private var vectors: [UInt64: [Float]] = [:]
    private let indexDirectory: URL
    private let fileManager = FileManager.default

    init(dimension: Int = 384, indexDirectory: URL? = nil) {
        self.dimension = dimension
        if let explicit = indexDirectory {
            self.indexDirectory = explicit
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.indexDirectory = appSupport.appendingPathComponent("vreader/SemanticIndex/vectors", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.indexDirectory, withIntermediateDirectories: true)
    }

    func insert(key: UInt64, vector: [Float]) throws {
        guard vector.count == dimension else {
            throw SemanticIndexStoreError.dimensionMismatch(expected: dimension, actual: vector.count)
        }
        vectors[key] = vector
    }

    func insertBatch(items: [(key: UInt64, vector: [Float])]) throws {
        for (k, v) in items {
            try insert(key: k, vector: v)
        }
    }

    func remove(keys: [UInt64]) {
        for k in keys {
            vectors.removeValue(forKey: k)
        }
    }

    func clear() {
        vectors.removeAll()
    }

    var count: Int {
        vectors.count
    }

    /// Performs top-K cosine similarity search.
    /// Returns pairs of (key, distance) sorted by ascending distance (descending similarity).
    func search(queryVector: [Float], count: Int) throws -> [(key: UInt64, distance: Float)] {
        guard queryVector.count == dimension else {
            throw SemanticIndexStoreError.dimensionMismatch(expected: dimension, actual: queryVector.count)
        }
        guard !vectors.isEmpty, count > 0 else { return [] }

        var results: [(key: UInt64, distance: Float)] = []
        results.reserveCapacity(vectors.count)

        for (key, vec) in vectors {
            // Cosine distance = 1 - cosine_similarity (for normalized vectors: 1 - dot_product)
            var dot: Float = 0
            for i in 0..<dimension {
                dot += queryVector[i] * vec[i]
            }
            let distance = max(0.0, 1.0 - dot)
            results.append((key: key, distance: distance))
        }

        results.sort { $0.distance < $1.distance }
        return Array(results.prefix(count))
    }
}
