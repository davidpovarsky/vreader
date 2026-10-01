// Purpose: Production MLX-backed embedding service using intfloat/multilingual-e5-small.
// Produces 384-dimensional unit-normalized embeddings with E5 prefixes.

import Foundation
import OSLog

#if canImport(MLXEmbedders)
import MLXEmbedders
#endif
#if canImport(MLXHuggingFace)
import MLXHuggingFace
#endif
#if canImport(HuggingFace)
import HuggingFace
#endif

final class MLXE5EmbeddingService: SemanticEmbeddingProviding, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.vreader.app", category: "MLXE5EmbeddingService")

    let dimension: Int
    let modelID: String
    private let fallback: MockSemanticEmbeddingService

    #if canImport(MLXEmbedders)
    private var container: EmbedderModelContainer?
    private let lock = NSLock()
    #endif

    init(
        dimension: Int = 384,
        modelID: String = AISemanticModelManager.modelIdentifier
    ) {
        self.dimension = dimension
        self.modelID = modelID
        self.fallback = MockSemanticEmbeddingService(dimension: dimension)
    }

    func loadModel(from directory: URL? = nil) async throws {
        #if canImport(MLXEmbedders)
        let config: ModelConfiguration
        if let directory {
            config = ModelConfiguration(directory: directory)
        } else {
            config = ModelConfiguration(id: modelID)
        }
        let loaded = try await EmbedderModelFactory.shared.loadContainer(configuration: config)
        lock.lock()
        self.container = loaded
        lock.unlock()
        Self.log.info("MLXE5EmbeddingService successfully loaded model \(self.modelID)")
        #endif
    }

    func embedQuery(_ text: String) async throws -> [Float] {
        try Task.checkCancellation()
        let formatted = AISemanticModelManager.formatQuery(text)
        return try await generateEmbedding(for: formatted)
    }

    func embedPassage(_ text: String) async throws -> [Float] {
        try Task.checkCancellation()
        let formatted = AISemanticModelManager.formatPassage(text)
        return try await generateEmbedding(for: formatted)
    }

    func embedPassages(_ texts: [String]) async throws -> [[Float]] {
        try Task.checkCancellation()
        guard !texts.isEmpty else { return [] }
        var allVectors: [[Float]] = []
        allVectors.reserveCapacity(texts.count)
        let batchSize = 32
        for i in stride(from: 0, to: texts.count, by: batchSize) {
            try Task.checkCancellation()
            let chunk = Array(texts[i..<min(i + batchSize, texts.count)])
            for text in chunk {
                let formatted = AISemanticModelManager.formatPassage(text)
                let vec = try await generateEmbedding(for: formatted)
                allVectors.append(vec)
            }
        }
        return allVectors
    }

    private func generateEmbedding(for text: String) async throws -> [Float] {
        #if canImport(MLXEmbedders)
        lock.lock()
        let activeContainer = container
        lock.unlock()

        if let activeContainer {
            let vector = try await activeContainer.perform { context in
                let output = context.encode(text)
                return output
            }
            guard vector.count == dimension else {
                throw SemanticIndexStoreError.dimensionMismatch(expected: dimension, actual: vector.count)
            }
            return normalize(vector)
        }
        #endif

        return try await fallback.embedPassage(text)
    }

    private func normalize(_ vector: [Float]) -> [Float] {
        let normSq = vector.reduce(0.0) { $0 + ($1 * $1) }
        let norm = sqrt(normSq)
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
