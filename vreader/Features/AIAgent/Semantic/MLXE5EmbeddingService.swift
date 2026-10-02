// Purpose: Production MLX-backed embedding service using intfloat/multilingual-e5-small.
// Produces 384-dimensional unit-normalized embeddings with E5 prefixes.

import Foundation
import OSLog

#if canImport(MLXEmbedders)
import MLXEmbedders
#endif
#if canImport(MLXLMCommon)
import MLXLMCommon
#endif
#if canImport(MLXHuggingFace)
import MLXHuggingFace
#endif
#if canImport(HuggingFace)
import HuggingFace
#endif
#if canImport(Tokenizers)
import Tokenizers
#endif

#if canImport(MLX)
import MLX
#endif

actor MLXE5EmbeddingService: SemanticEmbeddingProviding {
    private static let log = Logger(subsystem: "com.vreader.app", category: "MLXE5EmbeddingService")

    nonisolated let dimension: Int
    nonisolated let modelID: String

    #if canImport(MLXEmbedders)
    private var container: EmbedderModelContainer?
    #endif

    init(
        dimension: Int = 384,
        modelID: String = AISemanticModelManager.modelIdentifier
    ) {
        self.dimension = dimension
        self.modelID = modelID
    }

    func loadModel(from directory: URL? = nil) async throws {
        #if canImport(MLXEmbedders) && canImport(MLXLMCommon)
        let config: ModelConfiguration
        if let directory {
            config = ModelConfiguration(directory: directory)
        } else {
            config = ModelConfiguration(id: modelID)
        }
        #if canImport(MLXHuggingFace)
        let loaded = try await EmbedderModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: config
        )
        self.container = loaded
        #endif
        Self.log.info("MLXE5EmbeddingService successfully loaded model \(self.modelID)")
        #else
        throw SemanticModelError.modelNotLoaded
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
        try Task.checkCancellation()
        #if canImport(MLXEmbedders)
        guard let activeContainer = container else {
            throw SemanticModelError.modelNotLoaded
        }
        let vector = await activeContainer.perform { context -> [Float] in
            let inputTokens = context.tokenizer.encode(text: text, addSpecialTokens: true)
            // Clamp sequence length to 512 to prevent positional embedding bounds errors / NaNs
            let clampedTokens = Array(inputTokens.prefix(512))
            guard !clampedTokens.isEmpty else { return [] }
            #if canImport(MLX)
            let padded = MLXArray(clampedTokens.map { Int32($0) })
            let mask = MLXArray.ones(like: padded).asType(.bool)
            let tokenTypes = MLXArray.zeros(like: padded)
            let modelOutput = context.model(
                padded.expandedDimensions(axis: 0),
                positionIds: nil,
                tokenTypeIds: tokenTypes.expandedDimensions(axis: 0),
                attentionMask: mask.expandedDimensions(axis: 0)
            )
            let result = context.pooling(modelOutput, normalize: true, applyLayerNorm: false)
            result.eval()
            let squeezed = result.squeezed()
            return squeezed.asArray(Float.self)
            #else
            return []
            #endif
        }
        guard vector.count == dimension else {
            throw SemanticIndexStoreError.dimensionMismatch(expected: dimension, actual: vector.count)
        }
        guard vector.allSatisfy({ $0.isFinite }) else {
            throw SemanticModelError.inferenceFailed("Embedding contained non-finite values (NaN/Inf)")
        }
        return normalize(vector)
        #else
        throw SemanticModelError.modelNotLoaded
        #endif
    }

    private func normalize(_ vector: [Float]) -> [Float] {
        let normSq = vector.reduce(0.0) { $0 + ($1 * $1) }
        let norm = sqrt(normSq)
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
