// Purpose: Deterministic vector identity generation from SemanticChunk.id with collision resolution.
// Replaces unstable Swift Hasher and ephemeral process counters.

import Foundation
import CryptoKit

enum SemanticVectorKey {
    /// Deterministically derives a 64-bit unsigned integer from SHA-256 hash of the input string.
    static func deriveKey(for chunkID: String) -> UInt64 {
        let digest = SHA256.hash(data: Data(chunkID.utf8))
        return digest.withUnsafeBytes { ptr in
            ptr.load(as: UInt64.self)
        }
    }

    /// Derives an initial key for a chunk ID.
    static func deriveInitialKey(for chunkID: String) -> UInt64 {
        deriveKey(for: chunkID)
    }

    /// Resolves collisions deterministically given an existing key set or lookup dictionary.
    static func resolveKey(for chunkID: String, isKeyInUse: (UInt64) -> Bool) -> UInt64 {
        var candidate = deriveInitialKey(for: chunkID)
        var salt: UInt64 = 0
        while isKeyInUse(candidate) {
            salt &+= 1
            candidate = deriveKey(for: "\(chunkID)#salt:\(salt)")
        }
        return candidate
    }
}

/// A persistent, deterministic bidirectional mapping between chunk IDs and 64-bit vector keys.
struct SemanticVectorKeyTable: Codable, Sendable, Equatable {
    private(set) var chunkIDToKey: [String: UInt64] = [:]
    private(set) var keyToChunkID: [UInt64: String] = [:]

    init(chunkIDToKey: [String: UInt64] = [:], keyToChunkID: [UInt64: String] = [:]) {
        self.chunkIDToKey = chunkIDToKey
        self.keyToChunkID = keyToChunkID
    }

    /// Obtains the existing key for `chunkID`, or deterministically resolves and stores a new collision-free key.
    @discardableResult
    mutating func key(for chunkID: String) -> UInt64 {
        if let existing = chunkIDToKey[chunkID] {
            return existing
        }
        let resolved = SemanticVectorKey.resolveKey(for: chunkID) { key in
            if let assignedChunk = self.keyToChunkID[key] {
                return assignedChunk != chunkID
            }
            return false
        }
        chunkIDToKey[chunkID] = resolved
        keyToChunkID[resolved] = chunkID
        return resolved
    }

    func chunkID(for key: UInt64) -> String? {
        keyToChunkID[key]
    }

    mutating func remove(chunkID: String) {
        if let key = chunkIDToKey.removeValue(forKey: chunkID) {
            keyToChunkID.removeValue(forKey: key)
        }
    }

    mutating func remove(key: UInt64) {
        if let cid = keyToChunkID.removeValue(forKey: key) {
            chunkIDToKey.removeValue(forKey: cid)
        }
    }

    mutating func clear() {
        chunkIDToKey.removeAll()
        keyToChunkID.removeAll()
    }
}
