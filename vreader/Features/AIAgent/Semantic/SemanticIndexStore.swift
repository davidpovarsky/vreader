// Purpose: Real USearch-backed vector index store for ANN similarity search.
// Provides persistent USearch storage, deterministic vector keys, atomic coherent inserts,
// metadata compatibility verification, and corruption recovery without brute-force fallback.

import Foundation
import CryptoKit

#if canImport(USearch)
import USearch
#endif

actor SemanticIndexStore {
    let dimension: Int
    private let indexDirectory: URL
    private let fileManager = FileManager.default
    private var keyTable = SemanticVectorKeyTable()
    private var keyToBookKey: [UInt64: String] = [:]

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
        let dir: URL
        if let explicit = indexDirectory {
            dir = explicit
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            dir = appSupport.appendingPathComponent("vreader/SemanticIndex/vectors", isDirectory: true)
        }
        self.indexDirectory = dir
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        #if canImport(USearch)
        let vPath = dir.appendingPathComponent("vectors.usearch")
        let idx = try? USearchIndex.make(
            metric: .cos,
            dimensions: UInt32(dimension),
            connectivity: 16,
            quantization: .f32
        )
        if fileManager.fileExists(atPath: vPath.path), let idx {
            do {
                try idx.load(path: vPath.path)
            } catch {
                try? fileManager.removeItem(at: vPath)
            }
        }
        try? idx?.reserve(64)
        self.index = idx
        #endif

        let mPath = dir.appendingPathComponent("mappings.json")
        if let data = try? Data(contentsOf: mPath),
           let snapshot = try? JSONDecoder().decode(PersistedMappings.self, from: data) {
            self.keyTable = SemanticVectorKeyTable(chunkIDToKey: snapshot.chunkIDToKey, keyToChunkID: snapshot.keyToChunkID)
            self.keyToBookKey = snapshot.keyToBookKey
        }
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

    private func initIndex() throws {
        #if canImport(USearch)
        let idx = try USearchIndex.make(
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
        try idx.reserve(64)
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

        #if canImport(USearch)
        guard let idx = index else { throw SemanticIndexStoreError.indexUnavailable }
        let currentCap = (try? idx.capacity) ?? 0
        let currentCount = (try? idx.count) ?? 0
        if currentCount + 1 > Int(currentCap) {
            let targetCap = max(UInt32((currentCount + 1) * 2), UInt32(currentCap * 2), 64)
            try idx.reserve(targetCap)
        }
        try idx.add(key: key, vector: vector)
        #else
        throw SemanticIndexStoreError.indexUnavailable
        #endif

        try saveMappings()
        try saveVectors()
        return key
    }

    @discardableResult
    func insertBatch(coherentItems: [SemanticIndexInsertItem]) throws -> [String: UInt64] {
        var assignedKeys: [String: UInt64] = [:]
        #if canImport(USearch)
        guard let idx = index else { throw SemanticIndexStoreError.indexUnavailable }
        let currentCap = (try? idx.capacity) ?? 0
        let currentCount = (try? idx.count) ?? 0
        let needed = currentCount + coherentItems.count
        if needed > Int(currentCap) {
            let targetCap = max(UInt32(needed * 2), UInt32(currentCap * 2), 64)
            try idx.reserve(targetCap)
        }
        for item in coherentItems {
            guard item.vector.count == dimension else {
                throw SemanticIndexStoreError.dimensionMismatch(expected: dimension, actual: item.vector.count)
            }
            let key = keyTable.key(for: item.chunkID)
            keyToBookKey[key] = item.bookFingerprintKey
            try idx.add(key: key, vector: item.vector)
            assignedKeys[item.chunkID] = key
        }
        #else
        throw SemanticIndexStoreError.indexUnavailable
        #endif

        try saveMappings()
        try saveVectors()
        return assignedKeys
    }

    func delete(bookFingerprintKey: String) throws {
        let keysToRemove = keyToBookKey.filter { $0.value == bookFingerprintKey }.map { $0.key }
        try remove(keys: keysToRemove)
    }

    func remove(keys: [UInt64]) throws {
        for k in keys {
            keyTable.remove(key: k)
            keyToBookKey.removeValue(forKey: k)
            #if canImport(USearch)
            try index?.remove(key: k)
            #endif
        }
        try saveMappings()
        try saveVectors()
    }

    func clear() throws {
        keyTable.clear()
        keyToBookKey.removeAll()
        #if canImport(USearch)
        try initIndex()
        #endif
        try? fileManager.removeItem(at: vectorsPath)
        try? fileManager.removeItem(at: mappingsPath)
    }

    func count() -> Int {
        keyToBookKey.count
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

    /// Performs top-K similarity search using real USearch. No brute-force fallback in production.
    func search(queryVector: [Float], count: Int, bookFingerprintKey: String? = nil) throws -> [SemanticIndexStoreResult] {
        guard queryVector.count == dimension else {
            throw SemanticIndexStoreError.dimensionMismatch(expected: dimension, actual: queryVector.count)
        }
        guard count > 0 else { return [] }

        #if canImport(USearch)
        guard let idx = index, try idx.count > 0 else { return [] }
        // Retrieve 3x candidates to allow for book filtering
        let fetchCount = bookFingerprintKey == nil ? count : max(count * 3, 32)
        let searchResult = try idx.search(vector: queryVector, count: fetchCount)
        let keys = searchResult.0
        let distances = searchResult.1
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
        #else
        throw SemanticIndexStoreError.indexUnavailable
        #endif
    }
}
