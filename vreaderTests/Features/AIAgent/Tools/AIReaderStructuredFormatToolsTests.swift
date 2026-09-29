// Purpose: Format-specific reader context/chapter contracts for Feature #177 WI-6.

import Foundation
import Testing
@testable import vreader

@Suite("Feature #177 WI-6 — structured reader format tools")
struct AIReaderStructuredFormatToolsTests {
    @Test("get_current_context returns the exact PDF current page")
    @MainActor
    func contextUsesExactPDFPage() async {
        let fingerprint = WI6Fixtures.fingerprint("1", format: .pdf)
        let previous = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:1", index: 1,
            text: "PREVIOUS", page: 1, local: 0..<8
        )
        let current = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:2", index: 2,
            text: "EXACT-PDF-PAGE", page: 2, local: 0..<14
        )
        let result = await GetCurrentContextTool(
            context: makeContext(
                fingerprint: fingerprint, chunks: [previous, current],
                current: current, localBoundary: 14
            ),
            authorizationGate: neverGate()
        ).run(.object([:]))

        #expect(result.content.contains("EXACT-PDF-PAGE"))
        #expect(!result.content.contains("PREVIOUS"))
    }

    @Test("get_current_context returns the exact EPUB resource without flattening")
    @MainActor
    func contextUsesExactEPUBResource() async {
        let fingerprint = WI6Fixtures.fingerprint("2", format: .epub)
        let previous = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "epub:one.xhtml", index: 0,
            text: "PREVIOUS RESOURCE", href: "one.xhtml"
        )
        let current = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "epub:two.xhtml", index: 1,
            text: "EXACT EPUB RESOURCE", href: "two.xhtml"
        )
        let result = await GetCurrentContextTool(
            context: makeContext(
                fingerprint: fingerprint, chunks: [previous, current],
                current: current, localBoundary: nil
            ),
            authorizationGate: wholeBookGate()
        ).run(.object([:]))

        #expect(result.content.contains("EXACT EPUB RESOURCE"))
        #expect(!result.content.contains("PREVIOUS RESOURCE"))
    }

    @Test("oversized TXT chapter remains inside the established Chapter budget")
    @MainActor
    func oversizedChapterIsBounded() async {
        let fingerprint = WI6Fixtures.fingerprint("3", format: .txt)
        let count = AIContextBudget.defaultMaxUTF16 + 2_000
        let text = String(repeating: "x", count: count)
        let chunk = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "txt:segment:0", index: 0,
            text: text, local: 0..<count, global: 0..<count
        )
        let result = await GetCurrentChapterTool(
            context: makeContext(
                fingerprint: fingerprint, chunks: [chunk], current: chunk,
                localBoundary: count / 2, globalBoundary: count / 2,
                chapterBounds: ChapterBounds(startUTF16: 0, endUTF16: count)
            ),
            authorizationGate: wholeBookGate()
        ).run(.object([:]))
        let body = result.content.split(separator: "\n", maxSplits: 1)
            .last.map(String.init) ?? ""

        #expect(!result.isError)
        #expect(body.utf16.count <= AIContextBudget.defaultMaxUTF16)
    }

    @Test("get_current_chapter Ask withholds unread remainder until approval")
    @MainActor
    func chapterAskWaitsForApproval() async {
        let fingerprint = WI6Fixtures.fingerprint("4", format: .txt)
        let text = "READ-APPROVED-UNREAD"
        let chunk = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "txt:segment:0", index: 0,
            text: text, local: 0..<text.utf16.count, global: 0..<text.utf16.count
        )
        let store = WI6PreferencesStore(WI6Fixtures.preferences([
            .readCurrentBook: .allow, .readAhead: .allow,
        ], readAhead: .askBeforeReadingAhead))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let completion = WI6CompletionProbe()
        let tool = GetCurrentChapterTool(
            context: makeContext(
                fingerprint: fingerprint, chunks: [chunk], current: chunk,
                localBoundary: 4, globalBoundary: 4,
                chapterBounds: ChapterBounds(
                    startUTF16: 0, endUTF16: text.utf16.count
                )
            ),
            authorizationGate: AIAgentToolExecutionGate(
                preferencesStore: store, broker: broker,
                confirmationAvailability: .brokerConnected
            )
        )
        let task = Task {
            let result = await tool.run(.object([:]))
            await completion.markCompleted()
            return result
        }
        let request = await nextRequest(from: broker)
        #expect(!(await completion.completed))
        #expect(await broker.resolve(request.id, with: .allowOnce))
        let result = await task.value
        #expect(result.content.contains("APPROVED-UNREAD"))
    }

    @Test("EPUB chapter-equivalent is the exact current href resource")
    @MainActor
    func epubChapterUsesCurrentResource() async {
        let fingerprint = WI6Fixtures.fingerprint("5", format: .epub)
        let previous = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "epub:one.xhtml", index: 0,
            text: "PREVIOUS", href: "one.xhtml"
        )
        let current = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "epub:two.xhtml", index: 1,
            text: "CURRENT EPUB CHAPTER", href: "two.xhtml"
        )
        let result = await GetCurrentChapterTool(
            context: makeContext(
                fingerprint: fingerprint, chunks: [previous, current],
                current: current, localBoundary: nil
            ),
            authorizationGate: wholeBookGate()
        ).run(.object([:]))

        #expect(result.content.contains("CURRENT EPUB CHAPTER"))
        #expect(!result.content.contains("PREVIOUS"))
    }

    @Test("legacy chapter-equivalent degrades to the bounded current section")
    @MainActor
    func legacyChapterUsesCurrentSection() async {
        let fingerprint = WI6Fixtures.fingerprint("6", format: .azw3)
        let current = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "foliate:section:8", index: 8,
            text: "BOUNDED LEGACY SECTION", href: "section-8"
        )
        let result = await GetCurrentChapterTool(
            context: makeContext(
                fingerprint: fingerprint, chunks: [current],
                current: current, localBoundary: nil
            ),
            authorizationGate: wholeBookGate()
        ).run(.object([:]))
        #expect(result.content.contains("BOUNDED LEGACY SECTION"))
    }

    @MainActor
    private func makeContext(
        fingerprint: DocumentFingerprint,
        chunks: [AIDocumentChunk],
        current: AIDocumentChunk,
        localBoundary: Int?,
        globalBoundary: Int? = nil,
        chapterBounds: ChapterBounds? = nil
    ) -> AILiveReaderToolContext {
        let registry = AIDocumentProviderRegistry()
        let token = UUID()
        registry.attach(WI6DocumentProvider(
            fingerprint: fingerprint, chunks: chunks,
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fingerprint, current: current,
                localBoundary: localBoundary,
                globalBoundary: globalBoundary,
                chapterBounds: chapterBounds
            )
        ), for: AIDocumentSessionID(
            fingerprintKey: fingerprint.canonicalKey, readerToken: token
        ))
        return AILiveReaderToolContext(
            bookTitle: "Book", fingerprint: fingerprint,
            readerToken: token, providerResolver: registry
        )
    }

    private func neverGate() -> AIAgentToolExecutionGate {
        WI6Fixtures.gate([
            .readCurrentBook: .allow, .readAhead: .allow,
        ], readAhead: .neverReadAhead)
    }

    private func wholeBookGate() -> AIAgentToolExecutionGate {
        WI6Fixtures.gate([
            .readCurrentBook: .allow, .readAhead: .allow,
        ], readAhead: .wholeBookAllowed)
    }

    private func nextRequest(
        from broker: AIActionConfirmationBroker
    ) async -> AIActionConfirmationRequest {
        let stream = await broker.pendingRequestUpdates()
        for await requests in stream {
            if let request = requests.first { return request }
        }
        fatalError("confirmation stream ended before a request")
    }
}
