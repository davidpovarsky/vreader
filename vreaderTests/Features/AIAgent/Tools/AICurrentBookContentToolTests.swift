// Purpose: Structured current-book content authority contracts for Feature #177 WI-6.

import Foundation
import Testing
@testable import vreader

private actor WI6StructuredContentProvider: BookContentProvider {
    let info: BookContentInfo
    let flattened: String
    private(set) var extractionCalls = 0

    init(fingerprint: DocumentFingerprint, title: String, flattened: String) {
        info = BookContentInfo(
            fingerprintKey: fingerprint.canonicalKey,
            title: title,
            isReadable: true
        )
        self.flattened = flattened
    }

    func findBook(title: String) async -> BookTitleResolution {
        title == info.title ? .found(info) : .notFound
    }

    func extractText(fingerprintKey: String) async throws -> String {
        extractionCalls += 1
        return flattened
    }
}

@Suite("Feature #177 WI-6 — current-book content tool")
struct AICurrentBookContentToolTests {
    @Test("PDF current content uses exact page chunks and excludes later pages under Never")
    @MainActor
    func pdfUsesStructuredPageAuthority() async {
        let fingerprint = WI6Fixtures.fingerprint("9", format: .pdf)
        let current = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:2", index: 2,
            text: "CURRENT-PDF", page: 2, local: 0..<11
        )
        let future = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:3", index: 3,
            text: "FUTURE-PDF", page: 3, local: 0..<10
        )
        let provider = WI6StructuredContentProvider(
            fingerprint: fingerprint, title: "PDF",
            flattened: "WRONG-FLATTENED-PDF"
        )
        let result = await tool(
            fingerprint: fingerprint,
            title: "PDF",
            chunks: [current, future],
            current: current,
            boundary: 11,
            provider: provider,
            gate: neverGate()
        ).run(.object(["title": .string("PDF")]))

        #expect(result.content.contains("CURRENT-PDF"))
        #expect(!result.content.contains("FUTURE-PDF"))
        #expect(!result.content.contains("WRONG-FLATTENED-PDF"))
        #expect(await provider.extractionCalls == 0)
    }

    @Test("EPUB current content never falls back to flattened character authority")
    @MainActor
    func epubUsesStructuredResources() async {
        let fingerprint = WI6Fixtures.fingerprint("a", format: .epub)
        let current = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "epub:one.xhtml", index: 0,
            text: "CURRENT-EPUB", href: "one.xhtml"
        )
        let future = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "epub:two.xhtml", index: 1,
            text: "FUTURE-EPUB", href: "two.xhtml"
        )
        let provider = WI6StructuredContentProvider(
            fingerprint: fingerprint, title: "EPUB",
            flattened: "WRONG-FLATTENED-EPUB"
        )
        let result = await tool(
            fingerprint: fingerprint,
            title: "EPUB",
            chunks: [current, future],
            current: current,
            boundary: nil,
            provider: provider,
            gate: wholeBookGate()
        ).run(.object(["title": .string("EPUB")]))

        #expect(result.content.contains("CURRENT-EPUB"))
        #expect(result.content.contains("FUTURE-EPUB"))
        #expect(!result.content.contains("WRONG-FLATTENED-EPUB"))
        #expect(await provider.extractionCalls == 0)
    }

    @Test("Never clips a partial TXT unit and excludes later structured units")
    @MainActor
    func neverClipsTXTAndDropsFuture() async {
        let fingerprint = WI6Fixtures.fingerprint("b", format: .txt)
        let current = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "txt:segment:0", index: 0,
            text: "READ|UNREAD", local: 0..<11, global: 0..<11
        )
        let future = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "txt:segment:1", index: 1,
            text: "LATER", local: 0..<5, global: 11..<16
        )
        let provider = WI6StructuredContentProvider(
            fingerprint: fingerprint, title: "TXT", flattened: "FLAT-FUTURE"
        )
        let result = await tool(
            fingerprint: fingerprint,
            title: "TXT",
            chunks: [current, future],
            current: current,
            boundary: 4,
            globalBoundary: 4,
            provider: provider,
            gate: neverGate()
        ).run(.object(["title": .string("TXT")]))

        #expect(result.content.contains("READ"))
        #expect(!result.content.contains("UNREAD"))
        #expect(!result.content.contains("LATER"))
        #expect(await provider.extractionCalls == 0)
    }

    @Test("Ask keeps future structured content withheld until approval")
    @MainActor
    func askWaitsForFutureApproval() async {
        let fingerprint = WI6Fixtures.fingerprint("c", format: .pdf)
        let current = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:0", index: 0,
            text: "CURRENT", page: 0, local: 0..<7
        )
        let future = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:1", index: 1,
            text: "APPROVED-FUTURE", page: 1, local: 0..<15
        )
        let store = WI6PreferencesStore(WI6Fixtures.preferences([
            .readCurrentBook: .allow, .readAhead: .allow,
        ], readAhead: .askBeforeReadingAhead))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let completion = WI6CompletionProbe()
        let provider = WI6StructuredContentProvider(
            fingerprint: fingerprint, title: "Ask", flattened: "WRONG"
        )
        let contentTool = tool(
            fingerprint: fingerprint,
            title: "Ask",
            chunks: [current, future],
            current: current,
            boundary: 7,
            provider: provider,
            gate: AIAgentToolExecutionGate(
                preferencesStore: store, broker: broker,
                confirmationAvailability: .brokerConnected
            )
        )
        let task = Task {
            let result = await contentTool.run(.object(["title": .string("Ask")]))
            await completion.markCompleted()
            return result
        }
        let request = await nextRequest(from: broker)
        #expect(!(await completion.completed))
        #expect(await broker.resolve(request.id, with: .allowOnce))
        let result = await task.value

        #expect(result.content.contains("APPROVED-FUTURE"))
        #expect(await provider.extractionCalls == 0)
    }

    @Test("Whole-book mode may release a future structured unit")
    @MainActor
    func wholeBookReleasesFuture() async {
        let fingerprint = WI6Fixtures.fingerprint("d", format: .pdf)
        let current = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:0", index: 0,
            text: "CURRENT", page: 0, local: 0..<7
        )
        let future = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:9", index: 9,
            text: "WHOLE-FUTURE", page: 9, local: 0..<12
        )
        let provider = WI6StructuredContentProvider(
            fingerprint: fingerprint, title: "Whole", flattened: "WRONG"
        )
        let result = await tool(
            fingerprint: fingerprint,
            title: "Whole",
            chunks: [current, future],
            current: current,
            boundary: 7,
            provider: provider,
            gate: wholeBookGate()
        ).run(.object(["title": .string("Whole")]))
        #expect(result.content.contains("WHOLE-FUTURE"))
    }

    @Test("another unopened book retains extraction and ignores current-reader boundary")
    @MainActor
    func otherBookUsesExistingExtraction() async {
        let currentFingerprint = WI6Fixtures.fingerprint("e", format: .txt)
        let otherFingerprint = WI6Fixtures.fingerprint("f", format: .epub)
        let current = WI6Fixtures.chunk(
            fingerprint: currentFingerprint, id: "txt:segment:0", index: 0,
            text: "CURRENT", local: 0..<7, global: 0..<7
        )
        let provider = WI6StructuredContentProvider(
            fingerprint: otherFingerprint, title: "Other",
            flattened: "OTHER-FULL-CONTENT"
        )
        let result = await GetBookContentTool(
            provider: provider,
            authorizationGate: WI6Fixtures.gate([
                .readOtherBooks: .allow, .readCurrentBook: .deny,
            ]),
            readerContext: makeContext(
                fingerprint: currentFingerprint, title: "Current",
                chunks: [current], current: current, boundary: 1
            )
        ).run(.object(["title": .string("Other")]))

        #expect(result.content.contains("OTHER-FULL-CONTENT"))
        #expect(await provider.extractionCalls == 1)
    }

    @MainActor
    private func tool(
        fingerprint: DocumentFingerprint,
        title: String,
        chunks: [AIDocumentChunk],
        current: AIDocumentChunk,
        boundary: Int?,
        globalBoundary: Int? = nil,
        provider: WI6StructuredContentProvider,
        gate: AIAgentToolExecutionGate
    ) -> GetBookContentTool {
        GetBookContentTool(
            provider: provider,
            authorizationGate: gate,
            readerContext: makeContext(
                fingerprint: fingerprint, title: title, chunks: chunks,
                current: current, boundary: boundary,
                globalBoundary: globalBoundary
            )
        )
    }

    @MainActor
    private func makeContext(
        fingerprint: DocumentFingerprint,
        title: String,
        chunks: [AIDocumentChunk],
        current: AIDocumentChunk,
        boundary: Int?,
        globalBoundary: Int? = nil
    ) -> AILiveReaderToolContext {
        let registry = AIDocumentProviderRegistry()
        let token = UUID()
        registry.attach(WI6DocumentProvider(
            fingerprint: fingerprint, chunks: chunks,
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fingerprint, current: current,
                localBoundary: boundary, globalBoundary: globalBoundary
            )
        ), for: AIDocumentSessionID(
            fingerprintKey: fingerprint.canonicalKey, readerToken: token
        ))
        return AILiveReaderToolContext(
            bookTitle: title, fingerprint: fingerprint,
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
