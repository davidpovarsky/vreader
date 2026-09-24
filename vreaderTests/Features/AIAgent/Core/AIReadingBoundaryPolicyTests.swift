// Purpose: Feature #177 WI-2 RED contract for the one centralized spoiler policy.
// Every current-book retrieval tool must consume this decision instead of
// implementing page/href/offset checks independently.
//
// @coordinates-with: vreader/Features/AIAgent/Core/AIReadingBoundaryPolicy.swift

import Testing
#if !FEATURE_177_CORE_TESTS
@testable import vreader
#endif

@Suite("Feature #177 — spoiler/read-ahead boundary policy")
struct AIReadingBoundaryPolicyTests {
    private let fingerprint = DocumentFingerprint.validated(
        contentSHA256: String(repeating: "b", count: 64),
        fileByteCount: 8_192,
        format: .pdf
    )!

    private func locator(page: Int) -> Locator {
        Locator.validated(bookFingerprint: fingerprint, page: page)!
    }

    private var boundary: AIReadSoFarBoundary {
        AIReadSoFarBoundary(
            locator: locator(page: 49),
            sourceUnitID: "pdf-page-49",
            sourceUnitIndex: 49,
            localOffsetUTF16: 120
        )
    }

    private func chunk(
        page: Int,
        localStart: Int = 0,
        fingerprintKey: String? = nil
    ) -> AIDocumentChunk {
        AIDocumentChunk(
            id: "pdf:\(page):\(localStart)",
            bookFingerprintKey: fingerprintKey ?? fingerprint.canonicalKey,
            sourceUnitID: "pdf-page-\(page)",
            sourceUnitIndex: page,
            text: "text",
            locator: locator(page: page),
            sourceLabel: "Page \(page + 1)",
            chapterTitle: nil,
            pageIndex: page,
            href: nil,
            localStartUTF16: localStart,
            localEndUTF16: localStart + 4,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )
    }

    @Test("a prior page is allowed and not marked ahead")
    func priorPageAllowed() {
        let result = AIReadingBoundaryPolicy(mode: .neverReadAhead)
            .evaluate(candidate: chunk(page: 12), boundary: boundary)
        #expect(result == .allowed(aheadOfReader: false))
    }

    @Test("the unread tail of the current source unit is ahead")
    func unreadCurrentPageTailIsAhead() {
        let result = AIReadingBoundaryPolicy(mode: .neverReadAhead)
            .evaluate(candidate: chunk(page: 49, localStart: 121), boundary: boundary)
        #expect(result == .denied(aheadOfReader: true))
    }

    @Test("never mode denies a later page")
    func neverModeDeniesLaterPage() {
        let result = AIReadingBoundaryPolicy(mode: .neverReadAhead)
            .evaluate(candidate: chunk(page: 50), boundary: boundary)
        #expect(result == .denied(aheadOfReader: true))
    }

    @Test("ask mode requires confirmation for a later page")
    func askModeRequiresConfirmation() {
        let result = AIReadingBoundaryPolicy(mode: .askBeforeReadingAhead)
            .evaluate(candidate: chunk(page: 50), boundary: boundary)
        #expect(result == .requiresConfirmation(aheadOfReader: true))
    }

    @Test("whole-book mode permits but marks a later page")
    func wholeBookModeAllowsAndMarksAhead() {
        let result = AIReadingBoundaryPolicy(mode: .wholeBookAllowed)
            .evaluate(candidate: chunk(page: 50), boundary: boundary)
        #expect(result == .allowed(aheadOfReader: true))
    }

    @Test("PDF page fallback identifies a later page when source ordering is absent")
    func pdfPageFallbackIsKnownAhead() {
        let laterPage = AIDocumentChunk(
            id: "pdf-page-fallback",
            bookFingerprintKey: fingerprint.canonicalKey,
            sourceUnitID: "unknown-pdf-source",
            sourceUnitIndex: nil,
            text: "text",
            locator: locator(page: 50),
            sourceLabel: "Page 51",
            chapterTitle: nil,
            pageIndex: nil,
            href: nil,
            localStartUTF16: nil,
            localEndUTF16: nil,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )

        let result = AIReadingBoundaryPolicy(mode: .neverReadAhead)
            .evaluate(candidate: laterPage, boundary: boundary)
        #expect(result == .denied(aheadOfReader: true))
    }

    @Test("an exact current-position boundary includes text at its offset")
    func boundaryOffsetIsNotAhead() {
        let result = AIReadingBoundaryPolicy(mode: .neverReadAhead)
            .evaluate(candidate: chunk(page: 49, localStart: 120), boundary: boundary)
        #expect(result == .allowed(aheadOfReader: false))
    }

    @Test("unknown source ordering fails closed unless whole-book access is allowed")
    func unknownOrderingFailsClosed() {
        let unknownFingerprint = DocumentFingerprint.validated(
            contentSHA256: String(repeating: "c", count: 64),
            fileByteCount: 256,
            format: .txt
        )!
        let unknownLocator = Locator.validated(bookFingerprint: unknownFingerprint)!
        let unknownBoundary = AIReadSoFarBoundary(
            locator: unknownLocator,
            sourceUnitID: "known-text-source",
            sourceUnitIndex: nil,
            localOffsetUTF16: nil
        )
        let unknown = AIDocumentChunk(
            id: "unknown",
            bookFingerprintKey: unknownFingerprint.canonicalKey,
            sourceUnitID: "different-unknown-text-source",
            sourceUnitIndex: nil,
            text: "text",
            locator: unknownLocator,
            sourceLabel: nil,
            chapterTitle: nil,
            pageIndex: nil,
            href: nil,
            localStartUTF16: nil,
            localEndUTF16: nil,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )

        #expect(
            AIReadingBoundaryPolicy(mode: .neverReadAhead)
                .evaluate(candidate: unknown, boundary: unknownBoundary)
                == .denied(aheadOfReader: nil)
        )
        #expect(
            AIReadingBoundaryPolicy(mode: .askBeforeReadingAhead)
                .evaluate(candidate: unknown, boundary: unknownBoundary)
                == .requiresConfirmation(aheadOfReader: nil)
        )
        #expect(
            AIReadingBoundaryPolicy(mode: .wholeBookAllowed)
                .evaluate(candidate: unknown, boundary: unknownBoundary)
                == .allowed(aheadOfReader: nil)
        )
    }
}
