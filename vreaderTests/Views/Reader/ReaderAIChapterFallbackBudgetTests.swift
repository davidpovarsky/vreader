// Purpose: WI-4 regressions for format-aware Chapter fallback budgets.

import Foundation
import Testing
@testable import vreader

@Suite("Feature #177 WI-4 — Chapter fallback budgets")
@MainActor
struct ReaderAIChapterFallbackBudgetTests {
    @Test("PDF Chapter fallback uses current-page Section budget")
    func pdfChapterFallbackUsesSectionBudget() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("e", .pdf)
        let token = UUID()
        let other = chunk(
            fp, id: "pdf:page:3", index: 3,
            text: String(repeating: "OTHER PAGE ", count: 500), page: 3
        )
        let marker = "<<CURRENT PDF PAGE>>"
        let currentText = String(repeating: "P", count: 8_000) + marker
        let current = chunk(
            fp, id: "pdf:page:50", index: 50,
            text: currentText, page: 50
        )
        _ = registry.attach(
            StaticFinalCorrectionsProvider(
                fp: fp,
                snapshot: snapshot(
                    fp, .pdf, current,
                    boundaryLocal: currentText.utf16.count
                ),
                chunks: [other, current]
            ),
            for: session(fp, token)
        )

        let resolved = await coordinator(fp, token, registry)
            .resolveStructuredContext(for: .chapter)
        let result = try #require(resolved)

        #expect(result.text.utf16.count <= AIContextBudget.sectionMaxUTF16)
        #expect(result.text.contains(marker))
        #expect(result.sourceUnitIDs == ["pdf:page:50"])
        #expect(!result.text.contains("OTHER PAGE"))
    }

    @Test("Legacy Chapter fallback uses bounded Section budget")
    func legacyChapterFallbackUsesSectionBudget() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("f", .azw3)
        let token = UUID()
        let marker = "<<CURRENT FOLIATE SECTION>>"
        let currentText = String(repeating: "L", count: 4_000)
            + marker
            + String(repeating: "M", count: 4_000)
        let current = chunk(
            fp, id: "legacy:section:7", index: 7,
            text: currentText, href: "section-7"
        )
        _ = registry.attach(
            StaticFinalCorrectionsProvider(
                fp: fp,
                snapshot: snapshot(
                    fp, .azw3, current,
                    boundaryLocal: currentText.utf16.count / 2
                ),
                chunks: [current]
            ),
            for: session(fp, token)
        )
        let coordinator = coordinator(fp, token, registry)
        coordinator.loadedTextContent = "WRONG FLATTENED LEGACY BOOK"

        let resolved = await coordinator.resolveStructuredContext(for: .chapter)
        let result = try #require(resolved)

        #expect(result.text.utf16.count <= AIContextBudget.sectionMaxUTF16)
        #expect(result.text.contains(marker))
        #expect(result.sourceUnitIDs == ["legacy:section:7"])
        #expect(!result.text.contains("FLATTENED"))
    }

    @Test("EPUB Chapter keeps exact-resource Chapter budget")
    func epubChapterKeepsResourceChapterBudget() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("0", .epub)
        let token = UUID()
        let a = chunk(
            fp, id: "epub:a.xhtml", index: 0,
            text: "WRONG RESOURCE A", href: "a.xhtml",
            progression: 0.9, totalProgression: 0.99
        )
        let marker = "<<EXACT RESOURCE B>>"
        let bText = String(repeating: "B", count: 3_000)
            + marker
            + String(repeating: "C", count: 3_000)
        let b = chunk(
            fp, id: "epub:b.xhtml", index: 1,
            text: bText, href: "b.xhtml",
            progression: 0.5, totalProgression: 0.01
        )
        _ = registry.attach(
            StaticFinalCorrectionsProvider(
                fp: fp,
                snapshot: snapshot(fp, .epub, b, boundaryLocal: nil),
                chunks: [a, b]
            ),
            for: session(fp, token)
        )

        let resolved = await coordinator(fp, token, registry)
            .resolveStructuredContext(for: .chapter)
        let result = try #require(resolved)

        #expect(result.text.utf16.count > AIContextBudget.sectionMaxUTF16)
        #expect(result.text.utf16.count <= AIContextBudget.defaultMaxUTF16)
        #expect(result.text.contains(marker))
        #expect(result.sourceUnitIDs == ["epub:b.xhtml"])
        #expect(!result.text.contains("RESOURCE A"))
    }

    private func coordinator(
        _ fp: DocumentFingerprint,
        _ token: UUID,
        _ registry: AIDocumentProviderRegistry
    ) -> ReaderAICoordinator {
        ReaderAICoordinator(
            fallbackTitle: "Title",
            bookFormat: fp.format,
            fingerprintKey: fp.canonicalKey,
            readerToken: token,
            documentProviderResolver: registry
        )
    }

    private func fingerprint(
        _ digit: Character,
        _ format: BookFormat
    ) -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: digit, count: 64),
            fileByteCount: 10,
            format: format
        )
    }

    private func session(
        _ fp: DocumentFingerprint,
        _ token: UUID
    ) -> AIDocumentSessionID {
        AIDocumentSessionID(
            fingerprintKey: fp.canonicalKey,
            readerToken: token
        )
    }

    private func chunk(
        _ fp: DocumentFingerprint,
        id: String,
        index: Int,
        text: String,
        page: Int? = nil,
        href: String? = nil,
        progression: Double? = nil,
        totalProgression: Double? = nil
    ) -> AIDocumentChunk {
        let locator = Locator.validated(
            bookFingerprint: fp,
            href: href,
            progression: progression,
            totalProgression: totalProgression,
            page: page
        )!
        return AIDocumentChunk(
            id: id,
            bookFingerprintKey: fp.canonicalKey,
            sourceUnitID: id,
            sourceUnitIndex: index,
            text: text,
            locator: locator,
            sourceLabel: nil,
            chapterTitle: nil,
            pageIndex: page,
            href: href,
            localStartUTF16: 0,
            localEndUTF16: text.utf16.count,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )
    }

    private func snapshot(
        _ fp: DocumentFingerprint,
        _ format: BookFormat,
        _ current: AIDocumentChunk,
        boundaryLocal: Int?
    ) -> AIDocumentSnapshot {
        AIDocumentSnapshot(
            bookFingerprint: fp,
            format: format,
            currentLocator: current.locator,
            currentSourceUnitID: current.sourceUnitID,
            currentSectionChunks: [current],
            visibleChunks: [current],
            currentChapterLabel: nil,
            currentChapterBounds: nil,
            tocSummary: [],
            readSoFarBoundary: AIReadSoFarBoundary(
                locator: current.locator,
                sourceUnitID: current.sourceUnitID,
                sourceUnitIndex: current.sourceUnitIndex,
                localOffsetUTF16: boundaryLocal
            ),
            exactMappingAvailable: true
        )
    }
}
