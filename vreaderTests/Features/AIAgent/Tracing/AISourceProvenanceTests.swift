// Purpose: Unit tests for AISourceProvenance and ChatCitation conversion.
// Validates locator preservation, retrieval method tagging, and spoiler flags.

import Testing
import Foundation
@testable import vreader

@Suite("AISourceProvenanceTests")
struct AISourceProvenanceTests {

    @Test func sourceProvenanceMapsToChatCitationAccurately() {
        let fp = DocumentFingerprint(contentSHA256: String(repeating: "a", count: 64), fileByteCount: 1024, format: .epub)
        let locator = Locator(
            bookFingerprint: fp,
            href: "ch3.xhtml",
            progression: nil,
            totalProgression: nil,
            cfi: nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: nil,
            textContextBefore: nil,
            textContextAfter: nil
        )
        let prov = AISourceProvenance(
            bookFingerprintKey: "book-test",
            bookTitle: "Test Novel",
            locator: locator,
            sourceLabel: "Ch. 3",
            chapterTitle: "Chapter 3",
            pageIndex: nil,
            href: "ch3.xhtml",
            snippet: "The golden key was hidden under the floorboards.",
            retrievalMethod: .semanticSearch,
            score: 0.89,
            aheadOfReader: true,
            toolCallID: "call_sem_1"
        )

        let citation = prov.toChatCitation()

        #expect(citation.label == "Ch. 3")
        #expect(citation.sourceKind == .searchResult)
        #expect(citation.locator?.href == "ch3.xhtml")
        #expect(citation.aheadOfReader == true)
    }

    @Test func ocrProvenanceCarriesOCRFlag() {
        let prov = AISourceProvenance(
            bookFingerprintKey: "pdf-doc",
            pageIndex: 4,
            snippet: "Scanned diagram text",
            retrievalMethod: .ocr,
            isOCRDerived: true
        )

        #expect(prov.isOCRDerived == true)
        let citation = prov.toChatCitation()
        #expect(citation.label == "Page 5")
        #expect(citation.sourceKind == .searchResult)
    }
}
