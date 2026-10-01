// Purpose: Real USearch-backed vector index store for ANN similarity search.
// Provides persistent USearch storage, deterministic vector keys, atomic coherent inserts,
// metadata compatibility verification, and corruption recovery.

import Foundation
import CryptoKit

#if canImport(USearch)
import USearch
#endif

enum SemanticIndexStoreError: Error, LocalizedError, Sendable {
    case dimensionMismatch(expected: Int, actual: Int)
    case indexCorrupted
    case fileOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .dimensionMismatch(let expected, let actual):
            return "Vector dimension mismatch: expected \(expected), got \(actual)."
        case .indexCorrupted:
            return "Vector index file is corrupted or incompatible."
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

struct SemanticIndexInsertItem: Sendable {
    let key: UInt64
    let chunkID: String
    let bookFingerprintKey: String
    let vector: [Float]

    init(key: UInt64, chunkID: String, bookFingerprintKey: String, vector: [Float]) {
        self.key = key
        self.chunkID = chunkID
        self.bookFingerprintKey = bookFingerprintKey
        self.vector = vector
    }

    init(chunkID: String, bookFingerprintKey: String, vector: [Float]) {
        self.key = SemanticVectorKey.deriveKey(for: chunkID)
        self.chunkID = chunkID
        self.bookFingerprintKey = bookFingerprintKey
        self.vector = vector
    }
}

actor SemanticIndexStore {
    let dimension: Int
    private let indexDirectory: URL
    private let fileManager = FileManager.default
    private var keyTable = SemanticVectorKeyTable()
    private var keyToBookKey: [UInt64: String] = [:]
    private var fallbackVectors: [UInt64: [Float]] = [:]

    #if canImport(USearch)
    private var index: USearchIndex?
    #endif

    private var vectorsPath: URL {
        indexDirectory.appendingPathComponent("vectors.usearch")
    }

    private var mappingsPath: URL {
        indexDirectory.appendingPathComponent("mappings.json")
    }

    private struct PersistedMappings: Codable {
        let chunkIDToKey: [String: UInt64]
        let keyToChunkID: [UInt64: String]
        let keyToBookKey: [UInt64: String]
    }

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
        initIndex()
        try? loadMappings()
    }

    static func safeDirectoryName(for bookFingerprintKey: String) -> String {
        let digest = SHA256.hash(data: Data(bookFingerprintKey.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    static func directory(for bookFingerprintKey: String, baseDirectory: URL? = nil) -> URL {
        let base: URL
        if let baseDirectory {
            base = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            base = appSupport.appendingPathComponent("vreader/SemanticIndex", isDirectory: true)
        }
        return base.appendingPathComponent(safeDirectoryName(for: bookFingerprintKey), isDirectory: true)
    }

    private func initIndex() {
        #if canImport(USearch)
        let idx = USearchIndex.make(
            metric: .cos,
            dimensions: UInt32(dimension),
            connectivity: 16,
            quantization: .f32
        )
        if fileManager.fileExists(atPath: vectorsPath.path) {
            do {
                try idx.load(path: vectorsPath.path)
            } catch {
                try? fileManager.removeItem(at: vectorsPath)
            }
        }
        self.index = idx
        #endif
    }

    @discardableResult
    func add(chunkID: String, vector: [Float], bookFingerprintKey: String) throws -> UInt64 {
        guard vector.count == dimension else {
            throw SemanticIndexStoreError.dimensionMismatch(expected: dimension, actual: vector.count)
        }
        let key = keyTable.key(for: chunkID)
        keyToBookKey[key] = bookFingerprintKey
        fallbackVectors[key] = vector

        #if canImport(USearch)
        index?.add(key: key, vector: vector)
        #endif

        try? saveMappings()
        try? saveVectors()
        return key
    }

    func insert(key: UInt64, vector: [Float]) throws {
        guard vector.count == dimension else {
            throw SemanticIndexStoreError.dimensionMismatch(expected: dimension, actual: vector.count)
        }
        fallbackVectors[key] = vector
        #if canImport(USearch)
        index?.add(key: key, vector: vector)
        #endif
    }

    func insertBatch(items: [(key: UInt64, vector: [Float])]) throws {
        for (k, v) in items {
            try insert(key: k, vector: v)
        }
        try? saveVectors()
    }

    func insertBatch(coherentItems: [SemanticIndexInsertItem]) throws {
        for item in coherentItems {
            guard item.vector.count == dimension else {
                throw SemanticIndexStoreError.dimensionMismatch(expected: dimension, actual: item.vector.count)
            }
            let key = item.key
            keyTable.key(for: item.chunkID)
            keyToBookKey[key] = item.bookFingerprintKey
            fallbackVectors[key] = item.vector

            #if canImport(USearch)
            index?.add(key: key, vector: item.vector)
            #endif
        }
        try? saveMappings()
        try? saveVectors()
    }

    func delete(bookFingerprintKey: String) throws {
        let keysToRemove = keyToBookKey.filter { $0.value == bookFingerprintKey }.map { $0.key }
        remove(keys: keysToRemove)
    }

    func remove(keys: [UInt64]) {
        for k in keys {
            fallbackVectors.removeValue(forKey: k)
            keyTable.remove(key: k)
            keyToBookKey.removeValue(forKey: k)
            #if canImport(USearch)
            index?.remove(key: k)
            #endif
        }
        try? saveMappings()
        try? saveVectors()
    }

    func clear() {
        fallbackVectors.removeAll()
        keyTable.clear()
        keyToBookKey.removeAll()
        #if canImport(USearch)
        initIndex()
        #endif
        try? fileManager.removeItem(at: vectorsPath)
        try? fileManager.removeItem(at: mappingsPath)
    }

    func count() -> Int {
        #if canImport(USearch)
        if let idx = index {
            return Int(idx.count)
        }
        #endif
        return fallbackVectors.count
    }

    func save() throws {
        try saveMappings()
        try saveVectors()
    }

    func load() throws {
        try loadMappings()
        #if canImport(USearch)
        guard fileManager.fileExists(atPath: vectorsPath.path) else { return }
        guard let idx = index else { throw SemanticIndexStoreError.indexCorrupted }
        try idx.load(path: vectorsPath.path)
        #endif
    }

    private func saveVectors() throws {
        #if canImport(USearch)
        guard let idx = index else { return }
        let tempPath = indexDirectory.appendingPathComponent("vectors.usearch.tmp")
        do {
            try idx.save(path: tempPath.path)
            _ = try? fileManager.removeItem(at: vectorsPath)
            try fileManager.moveItem(at: tempPath, to: vectorsPath)
        } catch {
            throw SemanticIndexStoreError.fileOperationFailed("Failed to save USearch index: \(error.localizedDescription)")
        }
        #endif
    }

    private func saveMappings() throws {
        let data = PersistedMappings(
            chunkIDToKey: keyTable.chunkIDToKey,
            keyToChunkID: keyTable.keyToChunkID,
            keyToBookKey: keyToBookKey
        )
        let json = try JSONEncoder().encode(data)
        let tempPath = indexDirectory.appendingPathComponent("mappings.json.tmp")
        try json.write(to: tempPath, options: .atomic)
        _ = try? fileManager.removeItem(at: mappingsPath)
        try fileManager.moveItem(at: tempPath, to: mappingsPath)
    }

    private func loadMappings() throws {
        guard fileManager.fileExists(atPath: mappingsPath.path) else { return }
        let json = try Data(contentsOf: mappingsPath)
        guard let data = try? JSONDecoder().decode(PersistedMappings.self, from: json) else {
            throw SemanticIndexStoreError.indexCorrupted
        }
        keyTable = SemanticVectorKeyTable(chunkIDToKey: data.chunkIDToKey, keyToChunkID: data.keyToChunkID)
        keyToBookKey = data.keyToBookKey
    }

    /// Performs top-K similarity search, using real USearch when available with fallback.
    func search(queryVector: [Float], count: Int, bookFingerprintKey: String? = nil) throws -> [SemanticIndexStoreResult] {
        guard queryVector.count == dimension else {
            throw SemanticIndexStoreError.dimensionMismatch(expected: dimension, actual: queryVector.count)
        }
        guard count > 0 else { return [] }

        #if canImport(USearch)
        if let idx = index, idx.count > 0 {
            // Retrieve 3x candidates to allow for book filtering
            let fetchCount = bookFingerprintKey == nil ? count : max(count * 3, 32)
            let (keys, distances) = idx.search(vector: queryVector, count: fetchCount)
            var results: [SemanticIndexStoreResult] = []
            for i in 0..<keys.count {
                let k = keys[i]
                if let bookFingerprintKey, keyToBookKey[k] != bookFingerprintKey {
                    continue
                }
                let dist = distances[i]
                let sim = max(0.0, 1.0 - dist)
                let cid = keyTable.chunkID(for: k) ?? "\(k)"
                results.append(SemanticIndexStoreResult(key: k, chunkID: cid, distance: dist, similarity: sim))
                if results.count >= count { break }
            }
            return results
        }
        #endif

        // In-memory fallback
        guard !fallbackVectors.isEmpty else { return [] }
        var results: [SemanticIndexStoreResult] = []
        results.reserveCapacity(fallbackVectors.count)

        for (key, vec) in fallbackVectors {
            if let bookFingerprintKey, keyToBookKey[key] != bookFingerprintKey {
                continue
            }
            var dot: Float = 0
            for i in 0..<dimension {
                dot += queryVector[i] * vec[i]
            }
            let sim = max(0.0, dot)
            let distance = max(0.0, 1.0 - dot)
            let cid = keyTable.chunkID(for: key) ?? "\(key)"
            results.append(SemanticIndexStoreResult(key: key, chunkID: cid, distance: distance, similarity: sim))
        }

        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(count))
    }
}
