// Purpose: Tests for LocatorNormalizer — cross-mode locator/anchor normalization.
// Covers TXT, MD, EPUB, PDF round-trips plus edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("LocatorNormalizer")
struct LocatorNormalizerTests {

    // MARK: - Fixtures

    private static let txtFingerprint = DocumentFingerprint(
        contentSHA256: "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
        fileByteCount: 1000,
        format: .txt
    )

    private static let mdFingerprint = DocumentFingerprint(
        contentSHA256: "d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5",
        fileByteCount: 500,
        format: .md
    )

    private static let epubFingerprint = DocumentFingerprint(
        contentSHA256: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
        fileByteCount: 102_400,
        format: .epub
    )

    private static let pdfFingerprint = DocumentFingerprint(
        contentSHA256: "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3",
        fileByteCount: 204_800,
        format: .pdf
    )

    // MARK: - TXT Round-Trip

    @Test("TXT UTF-16 offset converts to canonical and back round-trips")
    func txtOffset_toCanonical_andBack_roundTrips() {
        let totalLength = 500
        let offset = 250
        let locator = Locator(
            bookFingerprint: Self.txtFingerprint,
            href: nil, progression: nil,
            totalProgression: Double(offset) / Double(totalLength),
            cfi: nil, page: nil,
            charOffsetUTF16: offset,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "sample text", textContextBefore: "before ", textContextAfter: " after"
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .txt, totalLengthUTF16: totalLength)

        #expect(restored.charOffsetUTF16 == offset)
        #expect(restored.totalProgression == locator.totalProgression)
        #expect(restored.bookFingerprint == Self.txtFingerprint)
    }

    // MARK: - MD Round-Trip

    @Test("MD UTF-16 offset converts to canonical and back round-trips")
    func mdOffset_toCanonical_andBack_roundTrips() {
        let totalLength = 300
        let offset = 150
        let locator = Locator(
            bookFingerprint: Self.mdFingerprint,
            href: nil, progression: nil,
            totalProgression: Double(offset) / Double(totalLength),
            cfi: nil, page: nil,
            charOffsetUTF16: offset,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "markdown text", textContextBefore: "pre ", textContextAfter: " post"
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .md)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .md, totalLengthUTF16: totalLength)

        #expect(restored.charOffsetUTF16 == offset)
        #expect(restored.totalProgression == locator.totalProgression)
        #expect(restored.bookFingerprint == Self.mdFingerprint)
    }

    // MARK: - EPUB Round-Trip

    @Test("EPUB href+progression converts to canonical and back round-trips")
    func epubHrefProgression_toCanonical_andBack_roundTrips() {
        let locator = Locator(
            bookFingerprint: Self.epubFingerprint,
            href: "chapter3.xhtml", progression: 0.75,
            totalProgression: 0.42,
            cfi: "/6/8[chap03]!/4/2/1:50", page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "epub text", textContextBefore: "before ", textContextAfter: " after"
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .epub)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .epub, totalLengthUTF16: nil)

        #expect(restored.href == "chapter3.xhtml")
        #expect(restored.progression == 0.75)
        #expect(restored.totalProgression == 0.42)
        #expect(restored.cfi == "/6/8[chap03]!/4/2/1:50")
        #expect(restored.bookFingerprint == Self.epubFingerprint)
    }

    // MARK: - PDF Round-Trip

    @Test("PDF page index converts to canonical and back round-trips")
    func pdfPage_toCanonical_andBack_roundTrips() {
        let totalPages = 100
        let page = 42
        let locator = Locator(
            bookFingerprint: Self.pdfFingerprint,
            href: nil, progression: nil,
            totalProgression: Double(page) / Double(totalPages),
            cfi: nil, page: page,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .pdf)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .pdf, totalLengthUTF16: nil)

        #expect(restored.page == page)
        #expect(restored.totalProgression == locator.totalProgression)
        #expect(restored.bookFingerprint == Self.pdfFingerprint)
    }

    // MARK: - Format-Independent Progression

    @Test("Canonical progression is format-independent (0 to 1)")
    func canonical_progression_isFormatIndependent() {
        // TXT at midpoint
        let txtLocator = Locator(
            bookFingerprint: Self.txtFingerprint,
            href: nil, progression: nil,
            totalProgression: 0.5,
            cfi: nil, page: nil,
            charOffsetUTF16: 250,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        // EPUB at midpoint
        let epubLocator = Locator(
            bookFingerprint: Self.epubFingerprint,
            href: "chapter5.xhtml", progression: 0.3,
            totalProgression: 0.5,
            cfi: nil, page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        let txtCanonical = LocatorNormalizer.toCanonical(txtLocator, format: .txt)
        let epubCanonical = LocatorNormalizer.toCanonical(epubLocator, format: .epub)

        // Both should have the same progression
        #expect(txtCanonical.progression == 0.5)
        #expect(epubCanonical.progression == 0.5)

        // Progression must be in [0, 1]
        #expect(txtCanonical.progression >= 0.0)
        #expect(txtCanonical.progression <= 1.0)
        #expect(epubCanonical.progression >= 0.0)
        #expect(epubCanonical.progression <= 1.0)
    }

    // MARK: - Highlight Anchor Normalization

    @Test("Highlight anchor normalization: TXT to canonical round-trips")
    func highlightAnchor_normalization_txtToCanonical_roundTrips() {
        let anchor = AnnotationAnchor.text(sourceUnitId: "main", startUTF16: 100, endUTF16: 200)
        let locator = Locator(
            bookFingerprint: Self.txtFingerprint,
            href: nil, progression: nil,
            totalProgression: 0.2,
            cfi: nil, page: nil,
            charOffsetUTF16: 100,
            charRangeStartUTF16: 100, charRangeEndUTF16: 200,
            textQuote: "highlighted text", textContextBefore: "before ", textContextAfter: " after"
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)

        // The native locator is preserved inside canonical
        #expect(canonical.nativeLocator.charRangeStartUTF16 == 100)
        #expect(canonical.nativeLocator.charRangeEndUTF16 == 200)
        #expect(canonical.textQuote == "highlighted text")

        // Round-trip back
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .txt, totalLengthUTF16: 500)
        #expect(restored.charRangeStartUTF16 == 100)
        #expect(restored.charRangeEndUTF16 == 200)

        // Anchor itself is not modified by normalizer (it only operates on Locator)
        if case .text(let unitId, let start, let end) = anchor {
            #expect(unitId == "main")
            #expect(start == 100)
            #expect(end == 200)
        }
    }

    @Test("Highlight anchor normalization: EPUB to canonical round-trips")
    func highlightAnchor_normalization_epubToCanonical_roundTrips() {
        let locator = Locator(
            bookFingerprint: Self.epubFingerprint,
            href: "chapter1.xhtml", progression: 0.25,
            totalProgression: 0.1,
            cfi: "/6/4[chap01]!/4/2/1:0", page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "epub highlight", textContextBefore: "before ", textContextAfter: " after"
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .epub)

        // Native locator preserved
        #expect(canonical.nativeLocator.href == "chapter1.xhtml")
        #expect(canonical.nativeLocator.cfi == "/6/4[chap01]!/4/2/1:0")
        #expect(canonical.textQuote == "epub highlight")

        // Round-trip
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .epub, totalLengthUTF16: nil)
        #expect(restored.href == "chapter1.xhtml")
        #expect(restored.cfi == "/6/4[chap01]!/4/2/1:0")
        #expect(restored.progression == 0.25)
    }

    // MARK: - Edge Cases

    @Test("Edge case: offset at document end")
    func edgeCases_offsetAtDocumentEnd() {
        let totalLength = 1000
        let locator = Locator(
            bookFingerprint: Self.txtFingerprint,
            href: nil, progression: nil,
            totalProgression: 1.0,
            cfi: nil, page: nil,
            charOffsetUTF16: totalLength,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        #expect(canonical.progression == 1.0)

        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .txt, totalLengthUTF16: totalLength)
        #expect(restored.charOffsetUTF16 == totalLength)
    }

    @Test("Edge case: empty document (zero length)")
    func edgeCases_emptyDocument() {
        let locator = Locator(
            bookFingerprint: Self.txtFingerprint,
            href: nil, progression: nil,
            totalProgression: 0.0,
            cfi: nil, page: nil,
            charOffsetUTF16: 0,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        #expect(canonical.progression == 0.0)

        // Round-trip with zero-length document
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .txt, totalLengthUTF16: 0)
        #expect(restored.charOffsetUTF16 == 0)
    }

    @Test("Edge case: zero progression (start of document)")
    func edgeCases_zeroProgression() {
        let locator = Locator(
            bookFingerprint: Self.epubFingerprint,
            href: "chapter1.xhtml", progression: 0.0,
            totalProgression: 0.0,
            cfi: nil, page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .epub)
        #expect(canonical.progression == 0.0)

        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .epub, totalLengthUTF16: nil)
        #expect(restored.totalProgression == 0.0)
    }

    // MARK: - Text Quote Preservation

    @Test("Text quote preserved for fuzzy matching through round-trip")
    func textQuote_preservedForFuzzyMatching() {
        let quote = "The quick brown fox jumps over the lazy dog"
        let ctxBefore = "Once upon a time, "
        let ctxAfter = " near the riverbank."

        let locator = Locator(
            bookFingerprint: Self.txtFingerprint,
            href: nil, progression: nil,
            totalProgression: 0.3,
            cfi: nil, page: nil,
            charOffsetUTF16: 150,
            charRangeStartUTF16: 150, charRangeEndUTF16: 193,
            textQuote: quote, textContextBefore: ctxBefore, textContextAfter: ctxAfter
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        #expect(canonical.textQuote == quote)
        #expect(canonical.textContextBefore == ctxBefore)
        #expect(canonical.textContextAfter == ctxAfter)

        // After round-trip, quote fields survive
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .txt, totalLengthUTF16: 500)
        #expect(restored.textQuote == quote)
        #expect(restored.textContextBefore == ctxBefore)
        #expect(restored.textContextAfter == ctxAfter)
    }

    // MARK: - Existing Locators Unmodified

    @Test("Normalization does not change existing locator fields")
    func existingLocators_unmodified() {
        let original = Locator(
            bookFingerprint: Self.epubFingerprint,
            href: "chapter2.xhtml", progression: 0.6,
            totalProgression: 0.35,
            cfi: "/6/6[chap02]!/4/2/1:20", page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "some quote", textContextBefore: "ctx-b", textContextAfter: "ctx-a"
        )

        // toCanonical operates on a copy, not the original
        let canonical = LocatorNormalizer.toCanonical(original, format: .epub)

        // The original locator is unchanged (struct semantics guarantee this,
        // but verify nativeLocator matches original)
        #expect(canonical.nativeLocator == original)
        #expect(canonical.nativeLocator.href == "chapter2.xhtml")
        #expect(canonical.nativeLocator.progression == 0.6)
        #expect(canonical.nativeLocator.cfi == "/6/6[chap02]!/4/2/1:20")
        #expect(canonical.nativeLocator.textQuote == "some quote")
    }

    // MARK: - Nil totalProgression Fallback

    @Test("TXT locator without totalProgression uses 0.0 as fallback")
    func txtLocator_nilTotalProgression_uses0() {
        let locator = Locator(
            bookFingerprint: Self.txtFingerprint,
            href: nil, progression: nil,
            totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: 100,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        #expect(canonical.progression == 0.0)
    }

    @Test("PDF locator without totalProgression uses 0.0 as fallback")
    func pdfLocator_nilTotalProgression_uses0() {
        let locator = Locator(
            bookFingerprint: Self.pdfFingerprint,
            href: nil, progression: nil,
            totalProgression: nil,
            cfi: nil, page: 5,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .pdf)
        #expect(canonical.progression == 0.0)
    }

    // MARK: - Progression Clamping

    @Test("Progression above 1.0 is clamped to 1.0")
    func progressionAbove1_isClamped() {
        let locator = Locator(
            bookFingerprint: Self.txtFingerprint,
            href: nil, progression: nil,
            totalProgression: 1.5,
            cfi: nil, page: nil,
            charOffsetUTF16: 600,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        #expect(canonical.progression == 1.0)
    }

    @Test("Negative progression is clamped to 0.0")
    func negativeProgression_isClamped() {
        let locator = Locator(
            bookFingerprint: Self.txtFingerprint,
            href: nil, progression: nil,
            totalProgression: -0.5,
            cfi: nil, page: nil,
            charOffsetUTF16: 0,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        #expect(canonical.progression == 0.0)
    }
}
