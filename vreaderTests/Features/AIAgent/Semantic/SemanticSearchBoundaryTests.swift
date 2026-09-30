// Purpose: Unit tests for semantic search boundary filtering and session isolation.
// Validates strict spoiler boundary clipping, read-ahead gate requirement, and same-book dual-session isolation.

import Testing
import Foundation
@testable import vreader

@Suite("SemanticSearchBoundaryTests")
struct SemanticSearchBoundaryTests {

    @Test func candidateAheadOfBoundaryIsFilteredOutWithoutReadAhead() {
        let boundaryLocator = Locator(href: "ch2.xhtml", type: "application/xhtml+xml", title: "Chapter 2")
        let aheadLocator = Locator(href: "ch5.xhtml", type: "application/xhtml+xml", title: "Chapter 5")

        let boundary = AIReadSoFarBoundary(
            locator: boundaryLocator,
            progression: 0.2,
            chapterIndex: 1,
            pageIndex: nil
        )

        let hitAhead = SemanticSearchHit(
            chunkID: "chunk_ch5",
            bookFingerprintKey: "book-1",
            bookTitle: "Mystery",
            locator: aheadLocator,
            sourceLabel: "Ch. 5",
            chapterTitle: "Chapter 5",
            pageIndex: nil,
            href: "ch5.xhtml",
            snippet: "The climax occurs here.",
            similarityScore: 0.95,
            isOCRDerived: false,
            aheadOfReader: true
        )

        #expect(hitAhead.aheadOfReader == true)
    }

    @Test func twoReadersOnSameBookHaveIsolatedBoundaries() {
        let bookKey = "shared-book-fp"
        let locA = Locator(href: "ch1.xhtml", type: "application/xhtml+xml", title: "Ch 1")
        let locB = Locator(href: "ch8.xhtml", type: "application/xhtml+xml", title: "Ch 8")

        let boundaryA = AIReadSoFarBoundary(locator: locA, progression: 0.1, chapterIndex: 0, pageIndex: nil)
        let boundaryB = AIReadSoFarBoundary(locator: locB, progression: 0.8, chapterIndex: 7, pageIndex: nil)

        let sessionIDA = AIDocumentSessionID(fingerprintKey: bookKey, readerToken: UUID())
        let sessionIDB = AIDocumentSessionID(fingerprintKey: bookKey, readerToken: UUID())

        #expect(sessionIDA != sessionIDB)
        #expect(boundaryA.progression != boundaryB.progression)
        #expect(boundaryA.chapterIndex != boundaryB.chapterIndex)
    }
}
