// Purpose: Semantic search service querying the vector index and mapping to structured source hits.
// Strictly enforces spoiler boundaries on current-book candidates before text is released.

import Foundation

struct SemanticSearchHit: Identifiable, Sendable, Equatable {
    var id: String { chunkID }
    let chunkID: String
    let bookFingerprintKey: String
    let bookTitle: String?
    let locator: Locator
    let sourceLabel: String?
    let chapterTitle: String?
    let pageIndex: Int?
    let href: String?
    let snippet: String
    let similarityScore: Double
    let isOCRDerived: Bool
    let aheadOfReader: Bool

    func toSourceProvenance(toolCallID: String? = nil) -> AISourceProvenance {
        AISourceProvenance(
            bookFingerprintKey: bookFingerprintKey,
            bookTitle: bookTitle,
            locator: locator,
            sourceLabel: sourceLabel,
            chapterTitle: chapterTitle,
            pageIndex: pageIndex,
            href: href,
            snippet: snippet,
            retrievalMethod: .semanticSearch,
            score: similarityScore,
            aheadOfReader: aheadOfReader,
            toolCallID: toolCallID,
            isOCRDerived: isOCRDerived
        )
    }
}

actor SemanticSearchService {
    private let embeddingService: any SemanticEmbeddingProviding
    private let metadataStore: SemanticIndexMetadataStore
    private let indexStore: SemanticIndexStore

    init(
        embeddingService: any SemanticEmbeddingProviding = MockSemanticEmbeddingService(),
        metadataStore: SemanticIndexMetadataStore = SemanticIndexMetadataStore(),
        indexStore: SemanticIndexStore = SemanticIndexStore()
    ) {
        self.embeddingService = embeddingService
        self.metadataStore = metadataStore
        self.indexStore = indexStore
    }

    /// Performs raw semantic search across vectors without spoiler boundary filtering.
    func searchRaw(query: String, maxHits: Int = 10) async throws -> [SemanticSearchHit] {
        try Task.checkCancellation()
        let queryVector = try await embeddingService.embedQuery(query)
        let matches = try await indexStore.search(queryVector: queryVector, count: maxHits)

        var hits: [SemanticSearchHit] = []
        for match in matches {
            guard let chunk = await metadataStore.fetchChunk(byVectorKey: match.key) else { continue }
            let similarity = max(0.0, 1.0 - Double(match.distance))
            hits.append(SemanticSearchHit(
                chunkID: chunk.chunkID,
                bookFingerprintKey: chunk.bookFingerprintKey,
                bookTitle: nil,
                locator: chunk.locator,
                sourceLabel: chunk.sourceLabel,
                chapterTitle: chunk.chapterTitle,
                pageIndex: chunk.pageIndex,
                href: chunk.href,
                snippet: chunk.snippet,
                similarityScore: similarity,
                isOCRDerived: chunk.isOCRDerived,
                aheadOfReader: false
            ))
        }
        return hits
    }

    /// Searches the current book with strict boundary enforcement.
    func searchCurrentBook(
        query: String,
        bookFingerprintKey: String,
        boundary: AIReadSoFarBoundary,
        readAheadAllowed: Bool,
        maxHits: Int = 8
    ) async throws -> [SemanticSearchHit] {
        let rawHits = try await searchRaw(query: query, maxHits: maxHits * 2)
        let bookHits = rawHits.filter { $0.bookFingerprintKey == bookFingerprintKey }

        var safeHits: [SemanticSearchHit] = []
        for hit in bookHits {
            let isAhead = isHitAheadOfBoundary(hit: hit, boundary: boundary)
            if isAhead && !readAheadAllowed {
                // Spoiler candidate suppressed in never/ask mode without approval
                continue
            }
            safeHits.append(SemanticSearchHit(
                chunkID: hit.chunkID,
                bookFingerprintKey: hit.bookFingerprintKey,
                bookTitle: hit.bookTitle,
                locator: hit.locator,
                sourceLabel: hit.sourceLabel,
                chapterTitle: hit.chapterTitle,
                pageIndex: hit.pageIndex,
                href: hit.href,
                snippet: hit.snippet,
                similarityScore: hit.similarityScore,
                isOCRDerived: hit.isOCRDerived,
                aheadOfReader: isAhead
            ))
            if safeHits.count >= maxHits { break }
        }
        return safeHits
    }

    private func isHitAheadOfBoundary(hit: SemanticSearchHit, boundary: AIReadSoFarBoundary) -> Bool {
        if let hitPage = hit.pageIndex, let bPage = boundary.sourceUnitIndex {
            return hitPage > bPage
        }
        if let hitProg = hit.locator.totalProgression, let bProg = boundary.locator.totalProgression {
            return hitProg > bProg
        }
        // Fail-safe: if ordering unknown and not same source unit, treat as ahead (fail closed)
        if let hitUnit = hit.locator.href, let bUnit = boundary.locator.href {
            return hitUnit != bUnit
        }
        return false
    }
}
