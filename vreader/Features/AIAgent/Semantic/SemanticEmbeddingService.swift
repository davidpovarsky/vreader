// Purpose: Embedding generation service protocol and implementations.
// Normalizes inputs with E5 prefixes and generates unit-normalized vectors.

import Foundation

enum SemanticModelError: LocalizedError, Equatable, Sendable {
    case modelNotInstalled
    case modelNotLoaded
    case inferenceFailed(String)
    case corruptedAssets(String)
    case dimensionMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "Semantic embedding model is not installed."
        case .modelNotLoaded:
            return "Semantic embedding model is not loaded in memory."
        case .inferenceFailed(let reason):
            return "Semantic model inference failed: \(reason)"
        case .corruptedAssets(let reason):
            return "Semantic model assets are corrupted or missing: \(reason)"
        case .dimensionMismatch(let expected, let actual):
            return "Vector dimension mismatch: expected \(expected), got \(actual)."
        }
    }
}

protocol SemanticEmbeddingProviding: Sendable {
    var dimension: Int { get }
    func embedQuery(_ text: String) async throws -> [Float]
    func embedPassage(_ text: String) async throws -> [Float]
    func embedPassages(_ texts: [String]) async throws -> [[Float]]
}

extension SemanticEmbeddingProviding {
    func embedPassage(_ text: String) async throws -> [Float] {
        let res = try await embedPassages([text])
        return res.first ?? [Float](repeating: 0.0, count: dimension)
    }
}

/// Deterministic embedding provider for CI and tests.
/// Computes normalized vectors using character/ngram frequency hashes
/// to ensure relevant Hebrew and English queries produce high cosine similarity with matching passages.
struct MockSemanticEmbeddingService: SemanticEmbeddingProviding {
    let dimension: Int

    init(dimension: Int = 384) {
        self.dimension = dimension
    }

    func embedQuery(_ text: String) async throws -> [Float] {
        try Task.checkCancellation()
        let formatted = AISemanticModelManager.formatQuery(text)
        return generateVector(for: formatted)
    }

    func embedPassage(_ text: String) async throws -> [Float] {
        try Task.checkCancellation()
        let formatted = AISemanticModelManager.formatPassage(text)
        return generateVector(for: formatted)
    }

    func embedPassages(_ texts: [String]) async throws -> [[Float]] {
        try Task.checkCancellation()
        return texts.map { text in
            let formatted = AISemanticModelManager.formatPassage(text)
            return generateVector(for: formatted)
        }
    }

    private func generateVector(for text: String) -> [Float] {
        var vector = [Float](repeating: 0.0, count: dimension)
        let clean = text.lowercased()
        let words = clean.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }

        for word in words {
            var hash: UInt64 = 5381
            for byte in word.utf8 {
                hash = ((hash << 5) &+ hash) &+ UInt64(byte)
            }
            let index = Int(hash % UInt64(dimension))
            vector[index] += 1.0
        }

        // Add character trigram weights for subword / Hebrew morphological overlap
        let chars = Array(clean)
        if chars.count >= 3 {
            for i in 0...(chars.count - 3) {
                let trigram = String(chars[i..<i+3])
                var hash: UInt64 = 5381
                for byte in trigram.utf8 {
                    hash = ((hash << 5) &+ hash) &+ UInt64(byte)
                }
                let index = Int(hash % UInt64(dimension))
                vector[index] += 0.5
            }
        }

        // L2 normalize
        let normSq = vector.reduce(0.0) { $0 + ($1 * $1) }
        let norm = sqrt(normSq)
        if norm > 0 {
            for i in 0..<dimension {
                vector[i] /= norm
            }
        } else {
            vector[0] = 1.0
        }
        return vector
    }
}
