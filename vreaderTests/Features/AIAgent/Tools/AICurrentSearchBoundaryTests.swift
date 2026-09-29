// Purpose: End-to-end FTS-result release contracts for Feature #177 WI-6.

import Foundation
import Testing
@testable import vreader

private actor WI6BoundarySearchSpy: SearchProviding {
    let page: SearchResultPage
    private(set) var calls = 0

    init(_ results: [SearchResult]) {
        page = SearchResultPage(
            results: results, page: 0, hasMore: false,
            totalEstimate: results.count
        )
    }

    func indexBook(
        fingerprint: DocumentFingerprint,
        textUnits: [TextUnit],
        segmentBaseOffsets: [Int: Int]?
    ) async throws {}

    func search(
        query: String,
        bookFingerprint: DocumentFingerprint,
        page: Int,
        pageSize: Int
    ) async throws -> SearchResultPage {
        calls += 1
        return self.page
    }

    func removeIndex(fingerprint: DocumentFingerprint) async throws {}
    func isIndexed(fingerprint: DocumentFingerprint) async -> Bool { true }
}
@Suite("Feature #177 WI-6 — current-search boundary integration")
struct AICurrentSearchBoundaryTests {
    @Test("current and behind exact hits survive while future and unknown hits fail closed")
    @MainActor
    func exactHitsAreReleasedByBoundary() async {
        let fingerprint = WI6Fixtures.fingerprint("4", format: .txt)
        let chunk = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "txt:segment:0", index: 0,
            text: "0123456789", local: 0..<10, global: 0..<10
        )
        let results = [
            result("behind", fingerprint: fingerprint, range: 1..<3),
            result("future-secret", fingerprint: fingerprint, range: 7..<9),
            SearchResult(
                id: "unknown", snippet: "unknown-secret",
                locator: WI6Fixtures.locator(fingerprint: fingerprint),
                sourceContext: "Unknown"
            ),
        ]
        let tool = SearchCurrentBookTool(
            search: WI6BoundarySearchSpy(results),
            bookFingerprint: fingerprint,
            authorizationGate: WI6Fixtures.gate([
                .readCurrentBook: .allow, .readAhead: .allow,
            ], readAhead: .neverReadAhead),
            readerContext: makeContext(
                fingerprint: fingerprint, chunks: [chunk], current: chunk,
                localBoundary: 5, globalBoundary: 5
            )
        )

        let output = await tool.run(.object(["query": .string("needle")]))
        #expect(output.content.contains("12"))
        #expect(!output.content.contains("future-secret"))
        #expect(!output.content.contains("unknown-secret"))
    }

    @Test("PDF current page is inclusive and a later page is excluded")
    @MainActor
    func pdfPageGranularity() async {
        let fingerprint = WI6Fixtures.fingerprint("5", format: .pdf)
        let current = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:2", index: 2,
            text: "CURRENT PAGE", page: 2, local: 0..<12
        )
        let future = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:3", index: 3,
            text: "FUTURE PAGE", page: 3, local: 0..<11
        )
        let search = WI6BoundarySearchSpy([
            SearchResult(
                id: "current", snippet: "CURRENT HIT", locator: current.locator,
                sourceContext: "Page 3"
            ),
            SearchResult(
                id: "future", snippet: "FUTURE HIT", locator: future.locator,
                sourceContext: "Page 4"
            ),
        ])
        let output = await SearchCurrentBookTool(
            search: search,
            bookFingerprint: fingerprint,
            authorizationGate: WI6Fixtures.gate([
                .readCurrentBook: .allow, .readAhead: .allow,
            ], readAhead: .neverReadAhead),
            readerContext: makeContext(
                fingerprint: fingerprint, chunks: [current, future],
                current: current, localBoundary: 12
            )
        ).run(.object(["query": .string("hit")]))

        #expect(output.content.contains("CURRENT HIT"))
        #expect(!output.content.contains("FUTURE HIT"))
    }

    @Test("Ask withholds an ahead FTS result until the broker approves it")
    @MainActor
    func askWaitsBeforeRelease() async {
        let fingerprint = WI6Fixtures.fingerprint("6", format: .pdf)
        let current = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:0", index: 0,
            text: "CURRENT", page: 0, local: 0..<7
        )
        let future = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:1", index: 1,
            text: "FUTURE", page: 1, local: 0..<6
        )
        let store = WI6PreferencesStore(WI6Fixtures.preferences([
            .readCurrentBook: .allow, .readAhead: .allow,
        ], readAhead: .askBeforeReadingAhead))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let completion = WI6CompletionProbe()
        let tool = SearchCurrentBookTool(
            search: WI6BoundarySearchSpy([
                SearchResult(
                    id: "future", snippet: "PROTECTED FUTURE",
                    locator: future.locator, sourceContext: "Page 2"
                ),
            ]),
            bookFingerprint: fingerprint,
            authorizationGate: AIAgentToolExecutionGate(
                preferencesStore: store, broker: broker,
                confirmationAvailability: .brokerConnected
            ),
            readerContext: makeContext(
                fingerprint: fingerprint, chunks: [current, future],
                current: current, localBoundary: 7
            )
        )
        let task = Task {
            let result = await tool.run(.object(["query": .string("future")]))
            await completion.markCompleted()
            return result
        }
        let request = await nextRequest(from: broker)
        #expect(!(await completion.completed))
        #expect(await broker.resolve(request.id, with: .allowOnce))
        let result = await task.value
        #expect(result.content.contains("PROTECTED FUTURE"))
    }

    @MainActor
    private func makeContext(
        fingerprint: DocumentFingerprint,
        chunks: [AIDocumentChunk],
        current: AIDocumentChunk,
        localBoundary: Int?,
        globalBoundary: Int? = nil
    ) -> AILiveReaderToolContext {
        let registry = AIDocumentProviderRegistry()
        let token = UUID()
        registry.attach(WI6DocumentProvider(
            fingerprint: fingerprint,
            chunks: chunks,
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fingerprint, current: current,
                localBoundary: localBoundary, globalBoundary: globalBoundary
            )
        ), for: AIDocumentSessionID(
            fingerprintKey: fingerprint.canonicalKey, readerToken: token
        ))
        return AILiveReaderToolContext(
            bookTitle: "Current", fingerprint: fingerprint,
            readerToken: token, providerResolver: registry
        )
    }

    private func result(
        _ snippet: String,
        fingerprint: DocumentFingerprint,
        range: Range<Int>
    ) -> SearchResult {
        SearchResult(
            id: snippet, snippet: snippet,
            locator: WI6Fixtures.locator(
                fingerprint: fingerprint, offset: range.lowerBound, range: range
            ),
            sourceContext: "Text"
        )
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
