// Purpose: Coordinates background indexing of books into the semantic index.
// Ensures actor-isolated serialization, one active job per book, cancellation, and progress observation.
// Preserves exact collision-assigned vector keys and exact UTF-16 ranges.

import Foundation
import OSLog

enum SemanticIndexingState: Sendable, Equatable {
    case idle
    case indexing(bookFingerprintKey: String, progress: Double)
    case completed(bookFingerprintKey: String)
    case failed(bookFingerprintKey: String, error: String)
    case cancelled(bookFingerprintKey: String)
}

actor SemanticIndexCoordinator {
    private static let log = Logger(subsystem: "com.vreader.app", category: "SemanticIndexCoordinator")

    private let embeddingService: any SemanticEmbeddingProviding
    private let metadataStore: SemanticIndexMetadataStore
    private let indexStore: SemanticIndexStore
    private let chunker: SemanticChunker

    private var activeTasks: [String: Task<Void, Error>] = [:]
    private(set) var currentState: SemanticIndexingState = .idle

    init(
        embeddingService: (any SemanticEmbeddingProviding)? = nil,
        metadataStore: SemanticIndexMetadataStore = SemanticIndexMetadataStore(),
        indexStore: SemanticIndexStore = SemanticIndexStore(),
        chunker: SemanticChunker = SemanticChunker()
    ) {
        self.embeddingService = embeddingService ?? MLXE5EmbeddingService()
        self.metadataStore = metadataStore
        self.indexStore = indexStore
        self.chunker = chunker
    }

    /// Indexes a document's chunks for a given book fingerprint.
    func indexBook(
        fingerprintKey: String,
        chunks: [AIDocumentChunk]
    ) async throws {
        if activeTasks[fingerprintKey] != nil {
            Self.log.info("Indexing already in flight for \(fingerprintKey)")
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performIndexing(fingerprintKey: fingerprintKey, chunks: chunks)
            } catch is CancellationError {
                await self.recordCancellation(fingerprintKey: fingerprintKey)
                throw CancellationError()
            } catch {
                await self.recordFailure(fingerprintKey: fingerprintKey, error: error.localizedDescription)
                throw error
            }
        }

        activeTasks[fingerprintKey] = task
        defer { activeTasks.removeValue(forKey: fingerprintKey) }
        try await task.value
    }

    private func performIndexing(
        fingerprintKey: String,
        chunks: [AIDocumentChunk]
    ) async throws {
        currentState = .indexing(bookFingerprintKey: fingerprintKey, progress: 0.0)

        // 1. Chunking
        try Task.checkCancellation()
        let semanticChunks = chunker.chunkDocument(chunks: chunks, bookFingerprintKey: fingerprintKey)
        guard !semanticChunks.isEmpty else {
            currentState = .completed(bookFingerprintKey: fingerprintKey)
            return
        }

        // 2. Embeddings
        var insertItems: [SemanticIndexInsertItem] = []
        let total = semanticChunks.count

        for (idx, sc) in semanticChunks.enumerated() {
            try Task.checkCancellation()
            let vector = try await embeddingService.embedPassages([sc.text]).first ?? []

            insertItems.append(SemanticIndexInsertItem(
                chunkID: sc.id,
                bookFingerprintKey: fingerprintKey,
                vector: vector
            ))

            let progress = Double(idx + 1) / Double(total)
            currentState = .indexing(bookFingerprintKey: fingerprintKey, progress: progress)
        }

        // 3. Save to Index with collision-safe key assignment and save to Metadata Store coherently
        let assignedKeys = try await indexStore.insertBatch(coherentItems: insertItems)

        var chunkMetadataList: [SemanticChunkMetadata] = []
        for sc in semanticChunks {
            let assignedKey = assignedKeys[sc.id] ?? SemanticVectorKey.deriveKey(for: sc.id)
            chunkMetadataList.append(SemanticChunkMetadata(
                chunkID: sc.id,
                vectorKey: assignedKey,
                bookFingerprintKey: fingerprintKey,
                sourceUnitID: sc.sourceUnitID,
                sourceUnitIndex: sc.sourceUnitIndex,
                sourceLabel: sc.sourceLabel,
                chapterTitle: sc.chapterTitle,
                pageIndex: sc.pageIndex,
                href: sc.href,
                snippet: String(sc.text.prefix(200)),
                locator: sc.locator,
                localStartUTF16: sc.localStartUTF16,
                localEndUTF16: sc.localEndUTF16,
                globalStartUTF16: sc.globalStartUTF16,
                globalEndUTF16: sc.globalEndUTF16,
                isOCRDerived: sc.isOCRDerived
            ))
        }

        let metadata = SemanticIndexMetadata(
            bookFingerprintKey: fingerprintKey,
            embeddingDimension: embeddingService.dimension,
            chunkCount: semanticChunks.count
        )
        try await metadataStore.save(metadata: metadata, chunks: chunkMetadataList)

        currentState = .completed(bookFingerprintKey: fingerprintKey)
        Self.log.info("Finished semantic indexing for \(fingerprintKey) (\(semanticChunks.count) chunks)")
    }

    func cancelIndexing(for fingerprintKey: String) {
        if let task = activeTasks[fingerprintKey] {
            task.cancel()
            activeTasks.removeValue(forKey: fingerprintKey)
            currentState = .cancelled(bookFingerprintKey: fingerprintKey)
        }
    }

    func removeBookIndex(fingerprintKey: String) async throws {
        cancelIndexing(for: fingerprintKey)
        try await metadataStore.remove(forBook: fingerprintKey)
        try await indexStore.delete(bookFingerprintKey: fingerprintKey)
    }

    func rebuildAll() async throws {
        for task in activeTasks.values { task.cancel() }
        activeTasks.removeAll()
        try await metadataStore.removeAll()
        try await indexStore.clear()
        currentState = .idle
    }

    private func recordCancellation(fingerprintKey: String) {
        currentState = .cancelled(bookFingerprintKey: fingerprintKey)
    }

    private func recordFailure(fingerprintKey: String, error: String) {
        currentState = .failed(bookFingerprintKey: fingerprintKey, error: error)
    }
}
