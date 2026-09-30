// Purpose: Unit tests for HybridSearchService reciprocal rank fusion.
// Validates combining lexical and semantic search results, deduplicating hits, and score merging.

import Testing
import Foundation
@testable import vreader

@Suite("HybridSearchServiceTests")
struct HybridSearchServiceTests {

    @Test func reciprocalRankFusionCombinesAndDedupes() {
        let hybrid = HybridSearchService(rrfK: 60)
        let loc1 = Locator(href: "ch1.xhtml", type: "application/xhtml+xml", title: "Chapter 1")
        let loc2 = Locator(href: "ch2.xhtml", type: "application/xhtml+xml", title: "Chapter 2")
        let loc3 = Locator(href: "ch3.xhtml", type: "application/xhtml+xml", title: "Chapter 3")

        let lexicalResults: [HybridSearchResultItem] = [
            HybridSearchResultItem(
                id: "item_1",
                bookFingerprintKey: "book-1",
                title: "Book One",
                locator: loc1,
                snippet: "Common passage matched both lexically and semantically.",
                method: .lexicalSearch,
                score: 10.0,
                aheadOfReader: false
            ),
            HybridSearchResultItem(
                id: "item_2",
                bookFingerprintKey: "book-1",
                title: "Book One",
                locator: loc2,
                snippet: "Lexical only passage.",
                method: .lexicalSearch,
                score: 5.0,
                aheadOfReader: false
            )
        ]

        let semanticResults: [HybridSearchResultItem] = [
            HybridSearchResultItem(
                id: "item_1", // Same item as in lexical
                bookFingerprintKey: "book-1",
                title: "Book One",
                locator: loc1,
                snippet: "Common passage matched both lexically and semantically.",
                method: .semanticSearch,
                score: 0.95,
                aheadOfReader: false
            ),
            HybridSearchResultItem(
                id: "item_3",
                bookFingerprintKey: "book-1",
                title: "Book One",
                locator: loc3,
                snippet: "Semantic only passage.",
                method: .semanticSearch,
                score: 0.85,
                aheadOfReader: false
            )
        ]

        let fused = hybrid.fuse(lexical: lexicalResults, semantic: semanticResults, limit: 10)

        #expect(fused.count == 3)
        // Item 1 should have highest combined RRF score because it appeared at rank 1 in both
        #expect(fused[0].id == "item_1")
        #expect(fused[0].score > fused[1].score)
    }

    @Test func emptyInputsYieldEmptyResult() {
        let hybrid = HybridSearchService()
        let fused = hybrid.fuse(lexical: [], semantic: [], limit: 5)
        #expect(fused.isEmpty)
    }

    @Test func limitTruncatesResults() {
        let hybrid = HybridSearchService()
        let items = (0..<10).map { idx in
            HybridSearchResultItem(
                id: "item_\(idx)",
                bookFingerprintKey: "book-1",
                title: "Book",
                locator: Locator(href: "c\(idx).xhtml", type: "text/html"),
                snippet: "Snippet \(idx)",
                method: .lexicalSearch,
                score: Double(10 - idx),
                aheadOfReader: false
            )
        }

        let fused = hybrid.fuse(lexical: items, semantic: [], limit: 3)
        #expect(fused.count == 3)
    }
}
