// Purpose: Feature #177 WI-6 RED contracts for exact live reader/context tools.

import Foundation
import Testing
@testable import vreader

@Suite("Feature #177 WI-6 — reader context tools")
struct AIReaderContextToolsTests {
    @Test("get_current_location reports exact PDF page")
    @MainActor
    func locationReportsPDFPage() async {
        let fp = WI6Fixtures.fingerprint("a", format: .pdf)
        let page = WI6Fixtures.chunk(
            fingerprint: fp, id: "pdf:page:4", index: 4,
            text: "page five", page: 4, local: 0..<9
        )
        let context = makeContext(
            title: "PDF Book", fingerprint: fp, chunks: [page],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fp, current: page, localBoundary: 9
            )
        )
        let result = await GetCurrentLocationTool(
            context: context,
            authorizationGate: allowCurrentGate()
        ).run(.object([:]))
        #expect(!result.isError)
        #expect(result.content.contains("PDF Book"))
        #expect(result.content.contains("page"))
        #expect(result.content.contains("5"))
    }

    @Test("get_current_location reports exact EPUB href without flattening")
    @MainActor
    func locationReportsEPUBHref() async {
        let fp = WI6Fixtures.fingerprint("b", format: .epub)
        let resource = WI6Fixtures.chunk(
            fingerprint: fp, id: "epub:Text/ch2.xhtml", index: 1,
            text: "chapter", href: "Text/ch2.xhtml", local: 0..<7
        )
        let context = makeContext(
            title: "EPUB", fingerprint: fp, chunks: [resource],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fp, current: resource, localBoundary: nil
            )
        )
        let result = await GetCurrentLocationTool(
            context: context, authorizationGate: allowCurrentGate()
        ).run(.object([:]))
        #expect(result.content.contains("Text/ch2.xhtml"))
        #expect(!result.content.contains("global_offset"))
    }

    @Test("same fingerprint readers resolve different exact sessions")
    @MainActor
    func sameBookReadersStayIsolated() async {
        let fp = WI6Fixtures.fingerprint("c", format: .pdf)
        let first = WI6Fixtures.chunk(
            fingerprint: fp, id: "pdf:page:0", index: 0,
            text: "FIRST", page: 0, local: 0..<5
        )
        let second = WI6Fixtures.chunk(
            fingerprint: fp, id: "pdf:page:8", index: 8,
            text: "SECOND", page: 8, local: 0..<6
        )
        let registry = AIDocumentProviderRegistry()
        let tokenA = UUID(), tokenB = UUID()
        registry.attach(WI6DocumentProvider(
            fingerprint: fp, chunks: [first],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fp, current: first, localBoundary: 5
            )
        ), for: AIDocumentSessionID(fingerprintKey: fp.canonicalKey, readerToken: tokenA))
        registry.attach(WI6DocumentProvider(
            fingerprint: fp, chunks: [second],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fp, current: second, localBoundary: 6
            )
        ), for: AIDocumentSessionID(fingerprintKey: fp.canonicalKey, readerToken: tokenB))

        let contextA = AILiveReaderToolContext(
            bookTitle: "Same", fingerprint: fp, readerToken: tokenA,
            providerResolver: registry
        )
        let contextB = AILiveReaderToolContext(
            bookTitle: "Same", fingerprint: fp, readerToken: tokenB,
            providerResolver: registry
        )
        let toolA = GetCurrentContextTool(
            context: contextA, authorizationGate: allowWholeCurrentGate()
        )
        let toolB = GetCurrentContextTool(
            context: contextB, authorizationGate: allowWholeCurrentGate()
        )
        let resultA = await toolA.run(.object([:]))
        let resultB = await toolB.run(.object([:]))
        #expect(resultA.content.contains("FIRST"))
        #expect(!resultA.content.contains("SECOND"))
        #expect(resultB.content.contains("SECOND"))
        #expect(!resultB.content.contains("FIRST"))
    }

    @Test("missing exact session fails safely instead of fingerprint fallback")
    @MainActor
    func missingSessionFailsClosed() async {
        let fp = WI6Fixtures.fingerprint("d", format: .pdf)
        let page = WI6Fixtures.chunk(
            fingerprint: fp, id: "pdf:page:1", index: 1,
            text: "OTHER SESSION", page: 1, local: 0..<13
        )
        let registry = AIDocumentProviderRegistry()
        registry.attach(WI6DocumentProvider(
            fingerprint: fp, chunks: [page],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fp, current: page, localBoundary: 13
            )
        ), for: AIDocumentSessionID(fingerprintKey: fp.canonicalKey, readerToken: UUID()))
        let missing = AILiveReaderToolContext(
            bookTitle: "Missing", fingerprint: fp, readerToken: UUID(),
            providerResolver: registry
        )
        let result = await GetCurrentContextTool(
            context: missing, authorizationGate: allowWholeCurrentGate()
        ).run(.object([:]))
        #expect(result.isError)
        #expect(!result.content.contains("OTHER SESSION"))
    }

    @Test("get_current_context uses exact structured section and Section budget")
    @MainActor
    func contextUsesStructuredSectionBudget() async {
        let fp = WI6Fixtures.fingerprint("e", format: .txt)
        let text = String(repeating: "x", count: AIContextBudget.sectionMaxUTF16 + 500)
        let chunk = WI6Fixtures.chunk(
            fingerprint: fp, id: "txt:segment:0", index: 0,
            text: text, local: 0..<text.utf16.count, global: 0..<text.utf16.count
        )
        let context = makeContext(
            title: "Long", fingerprint: fp, chunks: [chunk],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fp, current: chunk,
                localBoundary: text.utf16.count / 2,
                globalBoundary: text.utf16.count / 2
            )
        )
        let result = await GetCurrentContextTool(
            context: context, authorizationGate: allowWholeCurrentGate()
        ).run(.object([:]))
        #expect(!result.isError)
        let body = result.content.split(separator: "\n", maxSplits: 1).last.map(String.init) ?? ""
        #expect(body.utf16.count <= AIContextBudget.sectionMaxUTF16)
    }

    @Test("get_current_context Never does not leak current-unit unread suffix")
    @MainActor
    func contextNeverClipsUnreadSuffix() async {
        let fp = WI6Fixtures.fingerprint("f", format: .txt)
        let chunk = WI6Fixtures.chunk(
            fingerprint: fp, id: "txt:segment:0", index: 0,
            text: "READ|UNREAD", local: 0..<11, global: 0..<11
        )
        let context = makeContext(
            title: "Boundary", fingerprint: fp, chunks: [chunk],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fp, current: chunk,
                localBoundary: 4, globalBoundary: 4
            )
        )
        let result = await GetCurrentContextTool(
            context: context, authorizationGate: allowCurrentGate()
        ).run(.object([:]))
        #expect(result.content.contains("READ"))
        #expect(!result.content.contains("UNREAD"))
    }

    @Test("get_current_chapter uses TXT chapter bounds and clips at boundary")
    @MainActor
    func chapterUsesBoundsAndClips() async {
        let fp = WI6Fixtures.fingerprint("1", format: .txt)
        let chunk = WI6Fixtures.chunk(
            fingerprint: fp, id: "txt:segment:0", index: 0,
            text: "PREFIX-CHAPTER-FUTURE-SUFFIX", local: 0..<28, global: 0..<28
        )
        let context = makeContext(
            title: "Chapter", fingerprint: fp, chunks: [chunk],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fp, current: chunk,
                localBoundary: 14, globalBoundary: 14,
                chapterBounds: ChapterBounds(startUTF16: 7, endUTF16: 21)
            )
        )
        let result = await GetCurrentChapterTool(
            context: context, authorizationGate: allowCurrentGate()
        ).run(.object([:]))
        #expect(result.content.contains("CHAPTER"))
        #expect(!result.content.contains("FUTURE"))
        #expect(!result.content.contains("PREFIX"))
    }

    @Test("get_current_chapter PDF degrades to current page")
    @MainActor
    func chapterPDFSectionFallback() async {
        let fp = WI6Fixtures.fingerprint("2", format: .pdf)
        let page = WI6Fixtures.chunk(
            fingerprint: fp, id: "pdf:page:2", index: 2,
            text: "ONLY CURRENT PAGE", page: 2, local: 0..<17
        )
        let context = makeContext(
            title: "PDF", fingerprint: fp, chunks: [page],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fp, current: page, localBoundary: 17
            )
        )
        let result = await GetCurrentChapterTool(
            context: context, authorizationGate: allowCurrentGate()
        ).run(.object([:]))
        #expect(result.content.contains("ONLY CURRENT PAGE"))
    }

    @Test("get_table_of_contents preserves locators, caps honestly, and returns no body")
    @MainActor
    func tocPreservesAndCaps() async {
        let fp = WI6Fixtures.fingerprint("3", format: .epub)
        let resource = WI6Fixtures.chunk(
            fingerprint: fp, id: "epub:0.xhtml", index: 0,
            text: "SECRET BODY", href: "0.xhtml", local: 0..<11
        )
        let toc = (0..<5).map { index in
            AIDocumentTOCSummaryItem(
                id: "toc-\(index)", title: "Chapter \(index)", depth: index % 2,
                locator: WI6Fixtures.locator(
                    fingerprint: fp, href: "\(index).xhtml"
                )
            )
        }
        let context = makeContext(
            title: "TOC", fingerprint: fp, chunks: [resource],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fp, current: resource, localBoundary: nil, toc: toc
            )
        )
        let result = await GetTableOfContentsTool(
            context: context, authorizationGate: allowCurrentGate(), maxEntries: 2
        ).run(.object([:]))
        #expect(!result.isError)
        #expect(result.content.contains("Showing 2 of 5"))
        #expect(result.content.contains("0.xhtml"))
        #expect(!result.content.contains("SECRET BODY"))
    }

    private func allowCurrentGate() -> AIAgentToolExecutionGate {
        WI6Fixtures.gate([
            .readCurrentBook: .allow, .readAhead: .allow
        ], readAhead: .neverReadAhead)
    }

    private func allowWholeCurrentGate() -> AIAgentToolExecutionGate {
        WI6Fixtures.gate([
            .readCurrentBook: .allow, .readAhead: .allow
        ], readAhead: .wholeBookAllowed)
    }

    @MainActor
    private func makeContext(
        title: String,
        fingerprint: DocumentFingerprint,
        chunks: [AIDocumentChunk],
        snapshot: AIDocumentSnapshot
    ) -> AILiveReaderToolContext {
        let registry = AIDocumentProviderRegistry()
        let token = UUID()
        registry.attach(WI6DocumentProvider(
            fingerprint: fingerprint, chunks: chunks, snapshot: snapshot
        ), for: AIDocumentSessionID(
            fingerprintKey: fingerprint.canonicalKey, readerToken: token
        ))
        return AILiveReaderToolContext(
            bookTitle: title, fingerprint: fingerprint,
            readerToken: token, providerResolver: registry
        )
    }
}
