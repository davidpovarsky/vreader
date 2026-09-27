// Purpose: Focused WI-4 final-correction regressions for preserved Section
// budgets, EPUB flattened-text isolation, and exact-session late attachment.

import Foundation
import Observation
import Testing
@testable import vreader

@Suite("Feature #177 WI-4 — final correctness regressions", .serialized)
@MainActor
struct ReaderAIFinalCorrectionsIntegrationTests {
    private static let preservedSectionBudgetUTF16 = 2_500

    @Test("oversized TXT Section uses the preserved current-context budget")
    func structuredSectionUsesPreservedBudgetForOversizedTXTUnit() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("a", .txt)
        let token = UUID()
        let marker = "<<TXT CURRENT>>"
        let text = String(repeating: "A", count: 4_000)
            + marker
            + String(repeating: "B", count: 4_000)
        let offset = (text as NSString).range(of: marker).location
        let current = chunk(
            fp, id: "txt:segment:0", index: 0, text: text,
            globalStart: 0
        )
        let currentSnapshot = snapshot(
            fp, .txt, current,
            boundaryLocal: offset,
            boundaryGlobal: offset
        )
        _ = registry.attach(
            StaticFinalCorrectionsProvider(
                fp: fp, snapshot: currentSnapshot, chunks: [current]
            ),
            for: session(fp, token)
        )

        let resolved = await coordinator(fp, token, registry)
            .resolveStructuredContext(for: .section)
        let result = try #require(resolved)

        #expect(result.text.utf16.count <= Self.preservedSectionBudgetUTF16)
        #expect(result.text.contains(marker))
        #expect(result.sourceUnitIDs == ["txt:segment:0"])
    }

    @Test("oversized PDF Section stays on the exact page and uses the preserved budget")
    func structuredSectionUsesPreservedBudgetForOversizedPDFPage() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("b", .pdf)
        let token = UUID()
        let other = chunk(
            fp, id: "pdf:page:4", index: 4,
            text: String(repeating: "WRONG PAGE ", count: 400), page: 4
        )
        let marker = "<<PAGE 50 END>>"
        let page50Text = String(repeating: "P", count: 8_000) + marker
        let page50 = chunk(
            fp, id: "pdf:page:50", index: 50,
            text: page50Text, page: 50
        )
        _ = registry.attach(
            StaticFinalCorrectionsProvider(
                fp: fp,
                snapshot: snapshot(
                    fp, .pdf, page50,
                    boundaryLocal: page50Text.utf16.count
                ),
                chunks: [other, page50]
            ),
            for: session(fp, token)
        )

        let resolved = await coordinator(fp, token, registry)
            .resolveStructuredContext(for: .section)
        let result = try #require(resolved)

        #expect(result.text.utf16.count <= Self.preservedSectionBudgetUTF16)
        #expect(result.text.contains(marker))
        #expect(result.sourceUnitIDs == ["pdf:page:50"])
        #expect(!result.text.contains("WRONG PAGE"))
    }

    @Test("EPUB Chat ignores wrong flattened text and contradictory total progression")
    func epubChatUsesExactResourceAndPreservedSectionBudget() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("c", .epub)
        let token = UUID()
        let a = chunk(
            fp, id: "epub:a.xhtml", index: 0,
            text: "MISLEADING RESOURCE A", href: "a.xhtml",
            progression: 0.9, totalProgression: 0.99
        )
        let marker = "<<REAL RESOURCE B>>"
        let bText = String(repeating: "B", count: 4_000)
            + marker
            + String(repeating: "C", count: 4_000)
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
        let coordinator = coordinator(fp, token, registry)
        coordinator.loadedTextContent = "FLATTENED RESOURCE A — MUST NEVER WIN"

        await coordinator.refreshStructuredContext(for: .section)
        let result = try #require(coordinator.cachedStructuredContext(for: .section))

        #expect(coordinator.scopedChatContext(.section) == result.text)
        #expect(result.text.utf16.count <= Self.preservedSectionBudgetUTF16)
        #expect(result.text.contains(marker))
        #expect(result.sourceUnitIDs == ["epub:b.xhtml"])
        #expect(!result.text.contains("FLATTENED"))
        #expect(!result.text.contains("RESOURCE A"))
    }

    @Test("late exact-session attach automatically refreshes active Chat context")
    func lateExactSessionAttachAutomaticallyRefreshesChatContext() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("d", .epub)
        let token = UUID()
        let coordinator = coordinator(fp, token, registry)

        let previousOverride = AITestOverride.forceAvailable
        AITestOverride.forceAvailable = true
        defer { AITestOverride.forceAvailable = previousOverride }
        coordinator.setupIfNeeded()
        await coordinator.refreshChatContextNow()
        await Task.yield()
        let chat = try #require(coordinator.chatViewModel)
        #expect(chat.bookContext == "Title")

        let exact = chunk(
            fp, id: "epub:exact.xhtml", index: 1,
            text: "EXACT READER RESOURCE", href: "exact.xhtml"
        )
        let gated = GatedFinalCorrectionsProvider(
            fp: fp,
            snapshot: snapshot(fp, .epub, exact, boundaryLocal: nil),
            chunks: [exact]
        )
        _ = registry.attach(gated, for: session(fp, token))
        await gated.awaitSnapshotStarted()

        let other = chunk(
            fp, id: "epub:other.xhtml", index: 0,
            text: "OTHER READER RESOURCE", href: "other.xhtml"
        )
        _ = registry.attach(
            StaticFinalCorrectionsProvider(
                fp: fp,
                snapshot: snapshot(fp, .epub, other, boundaryLocal: nil),
                chunks: [other]
            ),
            for: session(fp, UUID())
        )

        var mutation = nextBookContextMutation(chat).makeAsyncIterator()
        gated.releaseSnapshot()
        _ = await mutation.next()

        #expect(chat.bookContext == "EXACT READER RESOURCE")
        #expect(coordinator.cachedStructuredContext(for: .chapter)?.sourceUnitIDs
            == ["epub:exact.xhtml"])
        #expect(chat.bookContext?.contains("OTHER READER") == false)
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
        totalProgression: Double? = nil,
        globalStart: Int? = nil
    ) -> AIDocumentChunk {
        let locator = Locator.validated(
            bookFingerprint: fp,
            href: href,
            progression: progression,
            totalProgression: totalProgression,
            page: page,
            charOffsetUTF16: globalStart
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
            globalStartUTF16: globalStart,
            globalEndUTF16: globalStart.map { $0 + text.utf16.count },
            isOCRDerived: false
        )
    }

    private func snapshot(
        _ fp: DocumentFingerprint,
        _ format: BookFormat,
        _ current: AIDocumentChunk,
        boundaryLocal: Int?,
        boundaryGlobal: Int? = nil
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
                localOffsetUTF16: boundaryLocal,
                globalOffsetUTF16: boundaryGlobal
            ),
            exactMappingAvailable: true
        )
    }

    private func nextBookContextMutation(
        _ chat: AIChatViewModel
    ) -> AsyncStream<Void> {
        let pair = AsyncStream<Void>.makeStream()
        withObservationTracking {
            _ = chat.bookContext
        } onChange: {
            pair.continuation.yield(())
            pair.continuation.finish()
        }
        return pair.stream
    }
}
