// Purpose: Comprehensive unit tests for SemanticChunker.
// Tests deterministic chunk ID generation, locator preservation, grapheme cluster boundaries,
// and Hebrew/multilingual handling.

import Testing
import Foundation
@testable import vreader

@Suite("SemanticChunkerTests")
struct SemanticChunkerTests {

    @Test func stableChunksForUnchangedInput() {
        let chunker = SemanticChunker(targetTokens: 100, overlapTokens: 15)
        let docChunk = AIDocumentChunk(
            unit: .chapter(title: "Chapter 1"),
            locator: Locator(href: "ch1.xhtml", type: "application/xhtml+xml", title: "Chapter 1"),
            text: "This is a test paragraph for semantic chunking that has multiple sentences. It should be chunked deterministically.",
            isSafeCurrentSection: true,
            isSafeBookSoFar: true,
            isAheadOfReader: false
        )

        let chunks1 = chunker.chunk(docChunk, bookFingerprintKey: "book-123")
        let chunks2 = chunker.chunk(docChunk, bookFingerprintKey: "book-123")

        #expect(chunks1.count == chunks2.count)
        #expect(!chunks1.isEmpty)
        #expect(chunks1[0].chunkID == chunks2[0].chunkID)
        #expect(chunks1[0].text == chunks2[0].text)
        #expect(chunks1[0].locator.href == "ch1.xhtml")
    }

    @Test func locatorPreservedAcrossChunks() {
        let chunker = SemanticChunker(targetTokens: 50, overlapTokens: 10)
        let locator = Locator(href: "page_5.pdf", type: "application/pdf", title: "Page 5")
        let longText = (0..<10).map { "Sentence number \($0) in this long document page." }.joined(separator: " ")
        let docChunk = AIDocumentChunk(
            unit: .page(number: 5),
            locator: locator,
            text: longText,
            isSafeCurrentSection: true,
            isSafeBookSoFar: true,
            isAheadOfReader: false,
            isOCRDerived: true
        )

        let chunks = chunker.chunk(docChunk, bookFingerprintKey: "pdf-book-xyz")

        #expect(!chunks.isEmpty)
        for chunk in chunks {
            #expect(chunk.locator.href == "page_5.pdf")
            #expect(chunk.isOCRDerived == true)
            #expect(chunk.bookFingerprintKey == "pdf-book-xyz")
        }
    }

    @Test func hebrewTextGraphemeClusterIntegrity() {
        let chunker = SemanticChunker(targetTokens: 50, overlapTokens: 10)
        let hebrewText = "שלום עולם! זהו טקסט בעברית המיועד לבדיקת פיצול סמנטי. אנחנו מוודאים שאין שבירת אותיות או ניקוד."
        let docChunk = AIDocumentChunk(
            unit: .chapter(title: "פרק א"),
            locator: Locator(href: "hebrew_ch1.xhtml", type: "application/xhtml+xml", title: "פרק א"),
            text: hebrewText,
            isSafeCurrentSection: true,
            isSafeBookSoFar: true,
            isAheadOfReader: false
        )

        let chunks = chunker.chunk(docChunk, bookFingerprintKey: "hebrew-book-001")

        #expect(!chunks.isEmpty)
        #expect(chunks[0].text.contains("שלום עולם"))
        #expect(chunks[0].chunkID.hasPrefix("sc_"))
    }

    @Test func emptyAndWhitespaceTextYieldsNoChunks() {
        let chunker = SemanticChunker()
        let docChunk = AIDocumentChunk(
            unit: .section(title: "Empty"),
            locator: Locator(href: "empty.xhtml", type: "application/xhtml+xml"),
            text: "   \n\n  \t  ",
            isSafeCurrentSection: true,
            isSafeBookSoFar: true,
            isAheadOfReader: false
        )

        let chunks = chunker.chunk(docChunk, bookFingerprintKey: "book-empty")
        #expect(chunks.isEmpty)
    }

    @Test func differentBookKeyProducesDifferentChunkID() {
        let chunker = SemanticChunker()
        let docChunk = AIDocumentChunk(
            unit: .chapter(title: "Ch 1"),
            locator: Locator(href: "ch1.xhtml", type: "application/xhtml+xml"),
            text: "Identical content in two different books.",
            isSafeCurrentSection: true,
            isSafeBookSoFar: true,
            isAheadOfReader: false
        )

        let chunksA = chunker.chunk(docChunk, bookFingerprintKey: "book-A")
        let chunksB = chunker.chunk(docChunk, bookFingerprintKey: "book-B")

        #expect(!chunksA.isEmpty && !chunksB.isEmpty)
        #expect(chunksA[0].chunkID != chunksB[0].chunkID)
    }
}
