// Purpose: Semantic search service querying the vector index and mapping to structured source hits.
// Strictly enforces spoiler boundaries on current-book candidates before text is released.
// Preserves exact UTF-16 and source unit ranges for exact partial-overlap clipping.

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
    let sourceUnitID: String?
    let sourceUnitIndex: Int?
    let localStartUTF16: Int?
    let localEndUTF16: Int?
    let globalStartUTF16: Int?
    let globalEndUTF16: Int?
    let isOCRDerived: Bool
    let aheadOfReader: Bool

    init(
        chunkID: String,
        bookFingerprintKey: String,
        bookTitle: String? = nil,
        locator: Locator,
        sourceLabel: String? = nil,
        chapterTitle: String? = nil,
        pageIndex: Int? = nil,
        href: String? = nil,
        snippet: String,
        similarityScore: Double,
        sourceUnitID: String? = nil,
        sourceUnitIndex: Int? = nil,
        localStartUTF16: Int? = nil,
        localEndUTF16: Int? = nil,
        globalStartUTF16: Int? = nil,
        globalEndUTF16: Int? = nil,
        isOCRDerived: Bool = false,
        aheadOfReader: Bool = false
    ) {
        self.chunkID = chunkID
        self.bookFingerprintKey = bookFingerprintKey
        self.bookTitle = bookTitle
        self.locator = locator
        self.sourceLabel = sourceLabel
        self.chapterTitle = chapterTitle
        self.pageIndex = pageIndex
        self.href = href
        self.snippet = snippet
        self.similarityScore = similarityScore
        self.sourceUnitID = sourceUnitID
        self.sourceUnitIndex = sourceUnitIndex
        self.localStartUTF16 = localStartUTF16
        self.localEndUTF16 = localEndUTF16
        self.globalStartUTF16 = globalStartUTF16
        self.globalEndUTF16 = globalEndUTF16
        self.isOCRDerived = isOCRDerived
        self.aheadOfReader = aheadOfReader
    }

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
        embeddingService: (any SemanticEmbeddingProviding)? = nil,
        metadataStore: SemanticIndexMetadataStore = SemanticIndexMetadataStore(),
        indexStore: SemanticIndexStore = SemanticIndexStore()
    ) {
        self.embeddingService = embeddingService ?? MLXE5EmbeddingService()
        self.metadataStore = metadataStore
        self.indexStore = indexStore
    }

    /// Searches the entire library across all indexed books.
    func searchLibrary(query: String, maxHits: Int = 10) async throws -> [SemanticSearchHit] {
        try await searchRaw(query: query, maxHits: maxHits)
    }

    /// Performs raw semantic search across vectors without spoiler boundary filtering.
    func searchRaw(query: String, maxHits: Int = 10) async throws -> [SemanticSearchHit] {
        try Task.checkCancellation()
        let queryVector = try await embeddingService.embedQuery(query)
        let matches = try await indexStore.search(queryVector: queryVector, count: maxHits)

        var hits: [SemanticSearchHit] = []
        for match in matches {
            var chunk = await metadataStore.fetchChunk(byVectorKey: match.key)
            if chunk == nil {
                chunk = await metadataStore.metadata(for: match.chunkID)
            }
            guard let chunk else { continue }
            let similarity = max(0.0, 1.0 - Double(match.distance))
            hits.append(SemanticSearchHit(
                chunkID: chunk.chunkID,
                bookFingerprintKey: chunk.bookFingerprintKey,
                bookTitle: chunk.bookTitle,
                locator: chunk.locator,
                sourceLabel: chunk.sourceLabel,
                chapterTitle: chunk.chapterTitle,
                pageIndex: chunk.pageIndex,
                href: chunk.href,
                snippet: chunk.snippet,
                similarityScore: similarity,
                sourceUnitID: chunk.sourceUnitID,
                sourceUnitIndex: chunk.sourceUnitIndex,
                localStartUTF16: chunk.localStartUTF16,
                localEndUTF16: chunk.localEndUTF16,
                globalStartUTF16: chunk.globalStartUTF16,
                globalEndUTF16: chunk.globalEndUTF16,
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
                sourceUnitID: hit.sourceUnitID,
                sourceUnitIndex: hit.sourceUnitIndex,
                localStartUTF16: hit.localStartUTF16,
                localEndUTF16: hit.localEndUTF16,
                globalStartUTF16: hit.globalStartUTF16,
                globalEndUTF16: hit.globalEndUTF16,
                isOCRDerived: hit.isOCRDerived,
                aheadOfReader: isAhead
            ))
            if safeHits.count >= maxHits { break }
        }
        return safeHits
    }

    private func isHitAheadOfBoundary(hit: SemanticSearchHit, boundary: AIReadSoFarBoundary) -> Bool {
        if let hitPage = hit.pageIndex, let bPage = boundary.pageIndex ?? boundary.sourceUnitIndex {
            return hitPage > bPage
        }
        if let hitProg = hit.locator.totalProgression ?? hit.locator.progression,
           let bProg = boundary.progression ?? boundary.locator.totalProgression ?? boundary.locator.progression {
            return hitProg > bProg
        }
        // Fail-safe: if ordering unknown and not same source unit, treat as ahead (fail closed)
        if let hitUnit = hit.locator.href, let bUnit = boundary.locator.href {
            return hitUnit != bUnit
        }
        return false
    }
}
