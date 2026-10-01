// Purpose: Hybrid search combining lexical FTS5 and semantic ANN results using Reciprocal Rank Fusion (RRF).
// Dedupes by canonical locator/snippet identity and preserves explainable scores and spoiler safety.

import Foundation

struct HybridSearchHit: Identifiable, Sendable, Equatable {
    var id: String { "\(bookFingerprintKey):\(locator.page ?? 0):\(locator.href ?? ""):\(snippet.prefix(30))" }
    let bookFingerprintKey: String
    let bookTitle: String?
    let locator: Locator
    let sourceLabel: String?
    let chapterTitle: String?
    let pageIndex: Int?
    let href: String?
    let snippet: String
    let rrfScore: Double
    let lexicalRank: Int?
    let semanticRank: Int?
    let isOCRDerived: Bool
    let aheadOfReader: Bool

    func toSourceProvenance(toolCallID: String? = nil) -> AISourceProvenance {
        let method: AIRetrievalMethod
        if lexicalRank != nil && semanticRank != nil {
            method = .semanticSearch // hybrid retrieval retains semantic & lexical evidence
        } else if semanticRank != nil {
            method = .semanticSearch
        } else {
            method = .lexicalSearch
        }
        return AISourceProvenance(
            bookFingerprintKey: bookFingerprintKey,
            bookTitle: bookTitle,
            locator: locator,
            sourceLabel: sourceLabel,
            chapterTitle: chapterTitle,
            pageIndex: pageIndex,
            href: href,
            snippet: snippet,
            retrievalMethod: method,
            score: rrfScore,
            aheadOfReader: aheadOfReader,
            toolCallID: toolCallID,
            isOCRDerived: isOCRDerived
        )
    }
}

struct HybridSearchResultItem: Identifiable, Sendable, Equatable {
    let id: String
    let bookFingerprintKey: String
    let title: String?
    let locator: Locator
    let snippet: String
    let method: AIRetrievalMethod
    let score: Double
    let aheadOfReader: Bool

    init(
        id: String,
        bookFingerprintKey: String,
        title: String?,
        locator: Locator,
        snippet: String,
        method: AIRetrievalMethod,
        score: Double,
        aheadOfReader: Bool
    ) {
        self.id = id
        self.bookFingerprintKey = bookFingerprintKey
        self.title = title
        self.locator = locator
        self.snippet = snippet
        self.method = method
        self.score = score
        self.aheadOfReader = aheadOfReader
    }
}

struct HybridSearchService: Sendable {
    static let kRRF: Double = 60.0
    let rrfK: Double

    init(rrfK: Double = 60.0) {
        self.rrfK = rrfK
    }

    /// Combines ordered lexical and semantic HybridSearchResultItems using Reciprocal Rank Fusion.
    func fuse(
        lexical: [HybridSearchResultItem],
        semantic: [HybridSearchResultItem],
        limit: Int = 10
    ) -> [HybridSearchResultItem] {
        var itemsByID: [String: (item: HybridSearchResultItem, score: Double)] = [:]
        var orderOfFirstSeen: [String] = []

        for (idx, lex) in lexical.enumerated() {
            let rrf = 1.0 / (rrfK + Double(idx + 1))
            itemsByID[lex.id] = (item: lex, score: rrf)
            orderOfFirstSeen.append(lex.id)
        }

        for (idx, sem) in semantic.enumerated() {
            let rrf = 1.0 / (rrfK + Double(idx + 1))
            if let existing = itemsByID[sem.id] {
                itemsByID[sem.id] = (item: existing.item, score: existing.score + rrf)
            } else {
                itemsByID[sem.id] = (item: sem, score: rrf)
                orderOfFirstSeen.append(sem.id)
            }
        }

        var fused: [HybridSearchResultItem] = []
        for id in orderOfFirstSeen {
            guard let entry = itemsByID.removeValue(forKey: id) else { continue }
            let updated = HybridSearchResultItem(
                id: entry.item.id,
                bookFingerprintKey: entry.item.bookFingerprintKey,
                title: entry.item.title,
                locator: entry.item.locator,
                snippet: entry.item.snippet,
                method: entry.item.method,
                score: entry.score,
                aheadOfReader: entry.item.aheadOfReader
            )
            fused.append(updated)
        }

        fused.sort { $0.score > $1.score }
        return Array(fused.prefix(limit))
    }

    /// Combines ordered lexical snippets and semantic hits into fused hybrid hits.
    static func fuse(
        lexicalHits: [SearchSnippet],
        semanticHits: [SemanticSearchHit],
        maxResults: Int = 10
    ) -> [HybridSearchHit] {
        var hitMap: [String: (lexical: (rank: Int, item: SearchSnippet)?, semantic: (rank: Int, item: SemanticSearchHit)?)] = [:]

        // 1. Lexical hits
        for (idx, lex) in lexicalHits.enumerated() {
            let key = makeDedupeKey(bookKey: lex.bookFingerprintKey, locator: lex.locator, snippet: lex.snippet)
            hitMap[key] = (lexical: (rank: idx + 1, item: lex), semantic: nil)
        }

        // 2. Semantic hits
        for (idx, sem) in semanticHits.enumerated() {
            let key = makeDedupeKey(bookKey: sem.bookFingerprintKey, locator: sem.locator, snippet: sem.snippet)
            if let existing = hitMap[key] {
                hitMap[key] = (lexical: existing.lexical, semantic: (rank: idx + 1, item: sem))
            } else {
                hitMap[key] = (lexical: nil, semantic: (rank: idx + 1, item: sem))
            }
        }

        // 3. Score with RRF
        var fused: [HybridSearchHit] = []
        for (_, entry) in hitMap {
            var score = 0.0
            var lRank: Int?
            var sRank: Int?

            if let l = entry.lexical {
                score += 1.0 / (kRRF + Double(l.rank))
                lRank = l.rank
            }
            if let s = entry.semantic {
                score += 1.0 / (kRRF + Double(s.rank))
                sRank = s.rank
            }

            // Pick locator & metadata from available entry
            guard let locator = entry.semantic?.item.locator ?? entry.lexical?.item.locator else {
                continue
            }
            let bookKey = entry.semantic?.item.bookFingerprintKey ?? entry.lexical?.item.bookFingerprintKey ?? ""
            let title = entry.semantic?.item.bookTitle ?? entry.lexical?.item.bookTitle
            let sourceLabel = entry.semantic?.item.sourceLabel ?? entry.lexical?.item.sourceLabel
            let chapter = entry.semantic?.item.chapterTitle ?? entry.lexical?.item.chapterTitle
            let page = entry.semantic?.item.pageIndex ?? entry.lexical?.item.pageIndex
            let href = entry.semantic?.item.href ?? entry.lexical?.item.href
            let snippet = entry.semantic?.item.snippet ?? entry.lexical?.item.snippet ?? ""
            let isOCR = entry.semantic?.item.isOCRDerived ?? false
            let isAhead = entry.semantic?.item.aheadOfReader ?? entry.lexical?.item.aheadOfReader ?? false

            fused.append(HybridSearchHit(
                bookFingerprintKey: bookKey,
                bookTitle: title,
                locator: locator,
                sourceLabel: sourceLabel,
                chapterTitle: chapter,
                pageIndex: page,
                href: href,
                snippet: snippet,
                rrfScore: score,
                lexicalRank: lRank,
                semanticRank: sRank,
                isOCRDerived: isOCR,
                aheadOfReader: isAhead
            ))
        }

        fused.sort { $0.rrfScore > $1.rrfScore }
        return Array(fused.prefix(maxResults))
    }

    private static func makeDedupeKey(bookKey: String, locator: Locator, snippet: String) -> String {
        let prefix = snippet.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30)
        return "\(bookKey):\(locator.page ?? -1):\(locator.href ?? ""):\(prefix)"
    }
}

/// Generic snippet protocol/struct for lexical search inputs to fuse with semantic hits.
struct SearchSnippet: Sendable, Equatable {
    let bookFingerprintKey: String
    let bookTitle: String?
    let locator: Locator
    let sourceLabel: String?
    let chapterTitle: String?
    let pageIndex: Int?
    let href: String?
    let snippet: String
    let aheadOfReader: Bool
}
