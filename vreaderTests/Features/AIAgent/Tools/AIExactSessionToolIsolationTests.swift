// Purpose: Same-book concurrent-reader integration coverage for all WI-6 reader seams.

import Foundation
import Testing
@testable import vreader

private actor WI6IsolationSearch: SearchProviding {
    let result: SearchResult

    init(result: SearchResult) {
        self.result = result
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
        SearchResultPage(
            results: [result], page: 0, hasMore: false, totalEstimate: 1
        )
    }

    func removeIndex(fingerprint: DocumentFingerprint) async throws {}
    func isIndexed(fingerprint: DocumentFingerprint) async -> Bool { true }
}

@Suite("Feature #177 WI-6 — exact reader-session tool isolation")
struct AIExactSessionToolIsolationTests {
    @Test("same-book location, chapter, search boundary, and navigation never cross reader tokens")
    @MainActor
    func readerToolsStayOnTheirExactSessions() async {
        let fingerprint = WI6Fixtures.fingerprint("0", format: .pdf)
        let pageA = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:1", index: 1,
            text: "READER-A-PAGE", page: 1, local: 0..<13
        )
        let pageB = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:7", index: 7,
            text: "READER-B-PAGE", page: 7, local: 0..<13
        )
        let registry = AIDocumentProviderRegistry()
        let tokenA = UUID(), tokenB = UUID()
        let contextA = attach(
            pageA, fingerprint: fingerprint, token: tokenA, registry: registry
        )
        let contextB = attach(
            pageB, fingerprint: fingerprint, token: tokenB, registry: registry
        )
        let gate = WI6Fixtures.gate([
            .readCurrentBook: .allow, .navigateReader: .allow,
            .readAhead: .allow,
        ], readAhead: .neverReadAhead)

        let locationA = await GetCurrentLocationTool(
            context: contextA, authorizationGate: gate
        ).run(.object([:]))
        let locationB = await GetCurrentLocationTool(
            context: contextB, authorizationGate: gate
        ).run(.object([:]))
        #expect(locationA.content.contains("\"page\":2"))
        #expect(locationB.content.contains("\"page\":8"))

        let chapterA = await GetCurrentChapterTool(
            context: contextA, authorizationGate: gate
        ).run(.object([:]))
        let chapterB = await GetCurrentChapterTool(
            context: contextB, authorizationGate: gate
        ).run(.object([:]))
        #expect(chapterA.content.contains("READER-A-PAGE"))
        #expect(!chapterA.content.contains("READER-B-PAGE"))
        #expect(chapterB.content.contains("READER-B-PAGE"))
        #expect(!chapterB.content.contains("READER-A-PAGE"))

        let sharedSearch = WI6IsolationSearch(result: SearchResult(
            id: "page-b", snippet: "READER-B-HIT", locator: pageB.locator,
            sourceContext: "Page 8"
        ))
        let searchA = await SearchCurrentBookTool(
            search: sharedSearch, bookFingerprint: fingerprint,
            authorizationGate: gate, readerContext: contextA
        ).run(.object(["query": .string("reader")]))
        let searchB = await SearchCurrentBookTool(
            search: sharedSearch, bookFingerprint: fingerprint,
            authorizationGate: gate, readerContext: contextB
        ).run(.object(["query": .string("reader")]))
        #expect(!searchA.content.contains("READER-B-HIT"))
        #expect(searchB.content.contains("READER-B-HIT"))

        let navigation = WI6NavigationSpy()
        _ = await OpenLocationTool(
            context: contextA, router: navigation, authorizationGate: gate
        ).run(locatorInput(pageA.locator))
        _ = await OpenLocationTool(
            context: contextB, router: navigation, authorizationGate: gate
        ).run(locatorInput(pageB.locator))
        let calls = await navigation.locations
        #expect(calls.count == 2)
        #expect(calls[0].1.readerToken == tokenA)
        #expect(calls[1].1.readerToken == tokenB)
    }

    @MainActor
    private func attach(
        _ chunk: AIDocumentChunk,
        fingerprint: DocumentFingerprint,
        token: UUID,
        registry: AIDocumentProviderRegistry
    ) -> AILiveReaderToolContext {
        registry.attach(WI6DocumentProvider(
            fingerprint: fingerprint, chunks: [chunk],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fingerprint, current: chunk,
                localBoundary: chunk.text.utf16.count
            )
        ), for: AIDocumentSessionID(
            fingerprintKey: fingerprint.canonicalKey, readerToken: token
        ))
        return AILiveReaderToolContext(
            bookTitle: "Same Book", fingerprint: fingerprint,
            readerToken: token, providerResolver: registry
        )
    }

    private func locatorInput(_ locator: Locator) -> JSONValue {
        .object([
            "locator_json": .string(try! AIReaderToolOutput.encode(locator)),
        ])
    }
}
