// Purpose: Integration tests verifying reading position, highlights, and bookmarks
// survive switching between Native and Unified modes via LocatorNormalizer.
//
// Key decisions:
// - Uses real LocatorNormalizer (no mocks) — validates actual round-trip fidelity.
// - Each test: create Locator → toCanonical → fromCanonical → verify match.
// - Covers TXT, MD, EPUB, PDF formats + edge cases.
//
// @coordinates-with LocatorNormalizer.swift, LocatorFactory.swift, FormatCapabilities.swift

import Testing
import Foundation
@testable import vreader

@Suite("Mode-Switch Persistence")
struct ModeSwitchPersistenceTests {

    // MARK: - Shared Fingerprints

    private static let txtFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233445566778899aabbccddeeff00112233445566778899aabb",
        fileByteCount: 4_096,
        format: .txt
    )

    private static let mdFP = DocumentFingerprint(
        contentSHA256: "bbccddee11223344556677889900aabbccddeeff11223344556677889900aabb",
        fileByteCount: 8_192,
        format: .md
    )

    private static let epubFP = DocumentFingerprint(
        contentSHA256: "ccddeeff22334455667788990011aabbccddeeff22334455667788990011aabb",
        fileByteCount: 524_288,
        format: .epub
    )

    private static let pdfFP = DocumentFingerprint(
        contentSHA256: "ddeeff0033445566778899001122aabbccddeeff33445566778899001122aabb",
        fileByteCount: 1_048_576,
        format: .pdf
    )

    // MARK: - TXT Format Tests

    @Test("TXT: position round-trips through native → canonical → native")
    func txt_position_nativeToCanonical_roundTrips() {
        let sourceText = "Hello world, this is a test document for mode switch persistence."
        let offset = 12  // start of "this"
        let totalLen = sourceText.utf16.count
        let progression = Double(offset) / Double(totalLen)

        let locator = LocatorFactory.txtPosition(
            fingerprint: Self.txtFP,
            charOffsetUTF16: offset,
            totalProgression: progression,
            sourceText: sourceText
        )!

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .txt, totalLengthUTF16: totalLen)

        #expect(restored.charOffsetUTF16 == offset)
        #expect(restored.totalProgression == locator.totalProgression)
        #expect(restored.bookFingerprint == Self.txtFP)
        #expect(restored.textQuote == locator.textQuote)
    }

    @Test("TXT: highlight anchor survives canonical conversion")
    func txt_highlight_nativeToCanonical_roundTrips() {
        let sourceText = "The quick brown fox jumps over the lazy dog near the river."
        let rangeStart = 10  // "brown"
        let rangeEnd = 15
        let totalLen = sourceText.utf16.count
        let progression = Double(rangeStart) / Double(totalLen)

        let locator = LocatorFactory.txtRange(
            fingerprint: Self.txtFP,
            charRangeStartUTF16: rangeStart,
            charRangeEndUTF16: rangeEnd,
            totalProgression: progression,
            sourceText: sourceText
        )!

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .txt, totalLengthUTF16: totalLen)

        #expect(restored.charRangeStartUTF16 == rangeStart)
        #expect(restored.charRangeEndUTF16 == rangeEnd)
        #expect(restored.textQuote == locator.textQuote)
        #expect(restored.textContextBefore == locator.textContextBefore)
        #expect(restored.textContextAfter == locator.textContextAfter)
    }

    @Test("TXT: bookmark locator survives canonical conversion")
    func txt_bookmark_nativeToCanonical_roundTrips() {
        let sourceText = "Chapter 1: The Beginning. Chapter 2: The Middle. Chapter 3: The End."
        let offset = 26  // start of "Chapter 2"
        let totalLen = sourceText.utf16.count
        let progression = Double(offset) / Double(totalLen)

        let locator = LocatorFactory.txtPosition(
            fingerprint: Self.txtFP,
            charOffsetUTF16: offset,
            totalProgression: progression,
            sourceText: sourceText
        )!

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .txt, totalLengthUTF16: totalLen)

        #expect(restored.charOffsetUTF16 == offset)
        #expect(restored.totalProgression == progression)
        #expect(restored.textQuote != nil)
    }

    // MARK: - MD Format Tests

    @Test("MD: position round-trips through canonical")
    func md_position_nativeToCanonical_roundTrips() {
        let sourceText = "# Heading\n\nSome markdown content with **bold** text."
        let offset = 11  // start of "Some"
        let totalLen = sourceText.utf16.count
        let progression = Double(offset) / Double(totalLen)

        let locator = LocatorFactory.mdPosition(
            fingerprint: Self.mdFP,
            charOffsetUTF16: offset,
            totalProgression: progression,
            sourceText: sourceText
        )!

        let canonical = LocatorNormalizer.toCanonical(locator, format: .md)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .md, totalLengthUTF16: totalLen)

        #expect(restored.charOffsetUTF16 == offset)
        #expect(restored.totalProgression == progression)
        #expect(restored.bookFingerprint == Self.mdFP)
    }

    @Test("MD: highlight anchor survives canonical conversion")
    func md_highlight_nativeToCanonical_roundTrips() {
        let sourceText = "# Title\n\nA paragraph with *emphasis* and `code` blocks."
        let rangeStart = 22  // "emphasis"
        let rangeEnd = 30
        let totalLen = sourceText.utf16.count
        let progression = Double(rangeStart) / Double(totalLen)

        let locator = LocatorFactory.mdRange(
            fingerprint: Self.mdFP,
            charRangeStartUTF16: rangeStart,
            charRangeEndUTF16: rangeEnd,
            totalProgression: progression,
            sourceText: sourceText
        )!

        let canonical = LocatorNormalizer.toCanonical(locator, format: .md)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .md, totalLengthUTF16: totalLen)

        #expect(restored.charRangeStartUTF16 == rangeStart)
        #expect(restored.charRangeEndUTF16 == rangeEnd)
        #expect(restored.textQuote == locator.textQuote)
    }

    // MARK: - EPUB Format Tests

    @Test("EPUB: position with href+progression survives canonical conversion")
    func epub_position_nativeToCanonical_roundTrips() {
        let locator = LocatorFactory.epub(
            fingerprint: Self.epubFP,
            href: "chapter3.xhtml",
            progression: 0.45,
            totalProgression: 0.35,
            cfi: "/6/4[chap03]!/4/2/1:42",
            textQuote: "It was the best of times",
            textContextBefore: "opening paragraph. ",
            textContextAfter: ", it was the worst"
        )!

        let canonical = LocatorNormalizer.toCanonical(locator, format: .epub)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .epub, totalLengthUTF16: nil)

        #expect(restored.href == "chapter3.xhtml")
        #expect(restored.progression == 0.45)
        #expect(restored.totalProgression == 0.35)
        #expect(restored.cfi == "/6/4[chap03]!/4/2/1:42")
        #expect(restored.textQuote == "It was the best of times")
        #expect(restored.bookFingerprint == Self.epubFP)
    }

    @Test("EPUB: highlight anchor survives canonical conversion")
    func epub_highlight_nativeToCanonical_roundTrips() {
        let locator = LocatorFactory.epub(
            fingerprint: Self.epubFP,
            href: "chapter5.xhtml",
            progression: 0.72,
            totalProgression: 0.60,
            cfi: "/6/10[chap05]!/4/2/3:10",
            textQuote: "To be or not to be",
            textContextBefore: "the famous soliloquy: ",
            textContextAfter: ", that is the question"
        )!

        let canonical = LocatorNormalizer.toCanonical(locator, format: .epub)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .epub, totalLengthUTF16: nil)

        #expect(restored.href == "chapter5.xhtml")
        #expect(restored.cfi == "/6/10[chap05]!/4/2/3:10")
        #expect(restored.textQuote == "To be or not to be")
        #expect(restored.textContextBefore == "the famous soliloquy: ")
        #expect(restored.textContextAfter == ", that is the question")
    }

    // MARK: - PDF Format Tests (Negative — PDF Stays Native)

    @Test("PDF: position round-trips as-is (no conversion needed)")
    func pdf_position_alwaysNative_noConversionNeeded() {
        let locator = LocatorFactory.pdf(
            fingerprint: Self.pdfFP,
            page: 42,
            totalProgression: 0.42,
            textQuote: "thermodynamic equilibrium"
        )!

        let canonical = LocatorNormalizer.toCanonical(locator, format: .pdf)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .pdf, totalLengthUTF16: nil)

        // PDF locator should pass through unchanged
        #expect(restored.page == 42)
        #expect(restored.totalProgression == 0.42)
        #expect(restored.textQuote == "thermodynamic equilibrium")
        #expect(restored.bookFingerprint == Self.pdfFP)
    }

    @Test("PDF: never gets unifiedReflow capability")
    func pdf_neverGetsUnifiedReflow() {
        let caps = FormatCapabilities.capabilities(for: .pdf)
        #expect(!caps.contains(.unifiedReflow))

        // Also verify with isComplexEPUB flag (irrelevant for PDF, but should not change)
        let capsWithFlag = FormatCapabilities.capabilities(for: .pdf, isComplexEPUB: true)
        #expect(!capsWithFlag.contains(.unifiedReflow))
    }

    // MARK: - Full Round-Trip Tests

    @Test("All formats: position round-trips native → canonical → native",
          arguments: [BookFormat.txt, BookFormat.md, BookFormat.epub, BookFormat.pdf])
    func allFormats_position_roundTrip_nativeCanonicalNative(format: BookFormat) {
        let locator: Locator
        let totalLengthUTF16: Int?

        switch format {
        case .txt:
            let text = "Sample text for round-trip testing."
            totalLengthUTF16 = text.utf16.count
            locator = LocatorFactory.txtPosition(
                fingerprint: Self.txtFP,
                charOffsetUTF16: 7,
                totalProgression: 7.0 / Double(text.utf16.count),
                sourceText: text
            )!
        case .md:
            let text = "# Title\n\nSample markdown content."
            totalLengthUTF16 = text.utf16.count
            locator = LocatorFactory.mdPosition(
                fingerprint: Self.mdFP,
                charOffsetUTF16: 10,
                totalProgression: 10.0 / Double(text.utf16.count),
                sourceText: text
            )!
        case .epub:
            totalLengthUTF16 = nil
            locator = LocatorFactory.epub(
                fingerprint: Self.epubFP,
                href: "ch1.xhtml",
                progression: 0.5,
                totalProgression: 0.25
            )!
        case .pdf:
            totalLengthUTF16 = nil
            locator = LocatorFactory.pdf(
                fingerprint: Self.pdfFP,
                page: 10,
                totalProgression: 0.1
            )!
        }

        // Native → Canonical
        let canonical = LocatorNormalizer.toCanonical(locator, format: format)

        // Canonical → Native
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: format, totalLengthUTF16: totalLengthUTF16)

        // Verify the restored locator exactly matches the original
        #expect(restored == locator, "Round-trip failed for format: \(format.rawValue)")
    }

    // MARK: - Edge Cases

    @Test("Edge case: position at document end survives conversion")
    func edgeCase_positionAtEnd_survivesConversion() {
        let sourceText = "Short text."
        let totalLen = sourceText.utf16.count
        // Position at the very end
        let offset = totalLen

        // Use Locator.validated directly since factory may reject offset == totalLen
        let locator = Locator.validated(
            bookFingerprint: Self.txtFP,
            totalProgression: 1.0,
            charOffsetUTF16: offset
        )!

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .txt, totalLengthUTF16: totalLen)

        #expect(restored.charOffsetUTF16 == offset)
        #expect(restored.totalProgression == 1.0)
        #expect(canonical.progression == 1.0)
    }

    @Test("Edge case: empty document survives conversion")
    func edgeCase_emptyDocument_survivesConversion() {
        let locator = Locator.validated(
            bookFingerprint: Self.txtFP,
            totalProgression: 0.0,
            charOffsetUTF16: 0
        )!

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .txt, totalLengthUTF16: 0)

        #expect(restored.charOffsetUTF16 == 0)
        #expect(restored.totalProgression == 0.0)
        #expect(canonical.progression == 0.0)
    }

    @Test("Edge case: multiple highlights all survive conversion")
    func edgeCase_multipleHighlights_allSurvive() {
        let sourceText = "Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda"
        let totalLen = sourceText.utf16.count

        // Define multiple highlight ranges
        let ranges: [(start: Int, end: Int)] = [
            (0, 5),    // "Alpha"
            (6, 10),   // "beta"
            (11, 16),  // "gamma"
            (17, 22),  // "delta"
            (23, 30),  // "epsilon"
        ]

        for range in ranges {
            let locator = LocatorFactory.txtRange(
                fingerprint: Self.txtFP,
                charRangeStartUTF16: range.start,
                charRangeEndUTF16: range.end,
                totalProgression: Double(range.start) / Double(totalLen),
                sourceText: sourceText
            )!

            let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
            let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .txt, totalLengthUTF16: totalLen)

            #expect(restored.charRangeStartUTF16 == range.start,
                    "Range start mismatch for [\(range.start)..\(range.end)]")
            #expect(restored.charRangeEndUTF16 == range.end,
                    "Range end mismatch for [\(range.start)..\(range.end)]")
            #expect(restored.textQuote == locator.textQuote,
                    "Quote mismatch for [\(range.start)..\(range.end)]")
        }
    }

    @Test("Edge case: zero progression survives conversion")
    func edgeCase_zeroProgression_survivesConversion() {
        let locator = LocatorFactory.epub(
            fingerprint: Self.epubFP,
            href: "cover.xhtml",
            progression: 0.0,
            totalProgression: 0.0
        )!

        let canonical = LocatorNormalizer.toCanonical(locator, format: .epub)

        #expect(canonical.progression == 0.0)

        let restored = LocatorNormalizer.fromCanonical(canonical, toFormat: .epub, totalLengthUTF16: nil)

        #expect(restored.progression == 0.0)
        #expect(restored.totalProgression == 0.0)
        #expect(restored.href == "cover.xhtml")
    }

    // MARK: - Canonical Position Validation

    @Test("Canonical position preserves native locator for lossless round-trip")
    func canonical_preservesNativeLocator() {
        let locator = LocatorFactory.epub(
            fingerprint: Self.epubFP,
            href: "chapter1.xhtml",
            progression: 0.33,
            totalProgression: 0.15,
            cfi: "/6/2!/4/1:0",
            textQuote: "In the beginning"
        )!

        let canonical = LocatorNormalizer.toCanonical(locator, format: .epub)

        // Canonical wraps the original locator
        #expect(canonical.nativeLocator == locator)
        #expect(canonical.progression == 0.15)  // from totalProgression
        #expect(canonical.textQuote == "In the beginning")
    }

    @Test("Canonical clamps progression outside 0-1 range")
    func canonical_clampsProgression() {
        // Locator with totalProgression > 1.0 (shouldn't happen but defensive)
        let locator = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: 1.5,
            cfi: nil, page: nil,
            charOffsetUTF16: 0,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        #expect(canonical.progression == 1.0)

        // Locator with negative totalProgression
        let locatorNeg = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: -0.5,
            cfi: nil, page: nil,
            charOffsetUTF16: 0,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        let canonicalNeg = LocatorNormalizer.toCanonical(locatorNeg, format: .txt)
        #expect(canonicalNeg.progression == 0.0)
    }

    @Test("Canonical defaults to 0.0 when totalProgression is nil")
    func canonical_defaultsToZeroWhenNil() {
        let locator = Locator.validated(
            bookFingerprint: Self.txtFP,
            charOffsetUTF16: 5
        )!

        // totalProgression is nil
        #expect(locator.totalProgression == nil)

        let canonical = LocatorNormalizer.toCanonical(locator, format: .txt)
        #expect(canonical.progression == 0.0)
    }
}
