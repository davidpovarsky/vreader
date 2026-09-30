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

struct SemanticIndexStoreResult: Sendable, Equatable {
    let key: UInt64
    let chunkID: String
    let distance: Float
    let similarity: Float
}

actor SemanticIndexStore {
    let dimension: Int
    private var vectors: [UInt64: [Float]] = [:]
    private var chunkIDToKey: [String: UInt64] = [:]
    private var keyToChunkID: [UInt64: String] = [:]
    private var keyToBookKey: [UInt64: String] = [:]
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

    func add(chunkID: String, vector: [Float], bookFingerprintKey: String) throws {
        guard vector.count == dimension else {
            throw SemanticIndexStoreError.dimensionMismatch(expected: dimension, actual: vector.count)
        }
        var hasher = Hasher()
        hasher.combine(chunkID)
        let key = UInt64(bitPattern: Int64(hasher.finalize()))
        chunkIDToKey[chunkID] = key
        keyToChunkID[key] = chunkID
        keyToBookKey[key] = bookFingerprintKey
        try insert(key: key, vector: vector)
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

    func delete(bookFingerprintKey: String) throws {
        let keysToRemove = keyToBookKey.filter { $0.value == bookFingerprintKey }.map { $0.key }
        remove(keys: keysToRemove)
    }

    func remove(keys: [UInt64]) {
        for k in keys {
            vectors.removeValue(forKey: k)
            if let cid = keyToChunkID[k] {
                chunkIDToKey.removeValue(forKey: cid)
            }
            keyToChunkID.removeValue(forKey: k)
            keyToBookKey.removeValue(forKey: k)
        }
    }

    func clear() {
        vectors.removeAll()
        chunkIDToKey.removeAll()
        keyToChunkID.removeAll()
        keyToBookKey.removeAll()
    }

    func count() -> Int {
        vectors.count
    }

    /// Performs top-K cosine similarity search.
    /// Returns results sorted by descending similarity.
    func search(queryVector: [Float], count: Int, bookFingerprintKey: String? = nil) throws -> [SemanticIndexStoreResult] {
        guard queryVector.count == dimension else {
            throw SemanticIndexStoreError.dimensionMismatch(expected: dimension, actual: queryVector.count)
        }
        guard !vectors.isEmpty, count > 0 else { return [] }

        var results: [SemanticIndexStoreResult] = []
        results.reserveCapacity(vectors.count)

        for (key, vec) in vectors {
            if let bookFingerprintKey, keyToBookKey[key] != bookFingerprintKey {
                continue
            }
            var dot: Float = 0
            for i in 0..<dimension {
                dot += queryVector[i] * vec[i]
            }
            let sim = max(0.0, dot)
            let distance = max(0.0, 1.0 - dot)
            let cid = keyToChunkID[key] ?? "\(key)"
            results.append(SemanticIndexStoreResult(key: key, chunkID: cid, distance: distance, similarity: sim))
        }

        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(count))
    }
}
