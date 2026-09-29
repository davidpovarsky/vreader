// Purpose: Feature #177 WI-6 RED contracts for authorization of existing tools.

import Foundation
import Testing
@testable import vreader

private actor WI6SearchSpy: SearchProviding {
    var page: SearchResultPage
    private(set) var calls = 0

    init(page: SearchResultPage = SearchResultPage(
        results: [], page: 0, hasMore: false, totalEstimate: 0
    )) { self.page = page }

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

private actor WI6LibrarySpy: LibrarySearchBackend {
    let books: [LibraryBookItem]
    private(set) var listCalls = 0
    private(set) var searchCalls = 0

    init(books: [LibraryBookItem]) { self.books = books }

    func libraryBooks() async throws -> [LibraryBookItem] {
        listCalls += 1
        return books
    }

    func indexState(fingerprintKey: String) async -> LibraryIndexState {
        LibraryIndexState(isIndexed: true, requiresReindex: false, segmentOffsets: nil)
    }

    func restoreSegmentOffsets(fingerprint: DocumentFingerprint, offsets: [Int: Int]) async {}

    func search(
        query: String,
        fingerprint: DocumentFingerprint,
        limit: Int
    ) async throws -> SearchResultPage {
        searchCalls += 1
        return SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
    }
}

private actor WI6ContentSpy: BookContentProvider {
    let resolution: BookTitleResolution
    let text: String
    private(set) var extractionCalls = 0

    init(resolution: BookTitleResolution, text: String = "protected content") {
        self.resolution = resolution
        self.text = text
    }

    func findBook(title: String) async -> BookTitleResolution { resolution }

    func extractText(fingerprintKey: String) async throws -> String {
        extractionCalls += 1
        return text
    }
}

@Suite("Feature #177 WI-6 — authorized existing tools")
struct AIAuthorizedExistingToolsTests {
    private let current = WI6Fixtures.fingerprint("a", format: .txt)
    private let other = WI6Fixtures.fingerprint("b", format: .epub)

    @Test("search_current_book Allow executes the FTS backend")
    @MainActor
    func currentSearchAllowExecutes() async {
        let search = WI6SearchSpy()
        let context = makeContext(fingerprint: current)
        let tool = SearchCurrentBookTool(
            search: search,
            bookFingerprint: current,
            authorizationGate: WI6Fixtures.gate([.readCurrentBook: .allow]),
            readerContext: context
        )
        _ = await tool.run(.object(["query": .string("needle")]))
        #expect(await search.calls == 1)
    }

    @Test("search_current_book Deny does not execute or expose the backend")
    @MainActor
    func currentSearchDenyStopsBackend() async {
        let search = WI6SearchSpy()
        let tool = SearchCurrentBookTool(
            search: search,
            bookFingerprint: current,
            authorizationGate: WI6Fixtures.gate([.readCurrentBook: .deny]),
            readerContext: makeContext(fingerprint: current)
        )
        let result = await tool.run(.object(["query": .string("needle")]))
        #expect(result.isError)
        #expect(await search.calls == 0)
        #expect(!result.content.contains("protected"))
    }

    @Test("search_current_book Ask denial never exposes a result")
    @MainActor
    func currentSearchAskDenial() async {
        let store = WI6PreferencesStore(WI6Fixtures.preferences([.readCurrentBook: .ask]))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let search = WI6SearchSpy()
        let resolver = resolveNextWI6Confirmation(on: broker, with: .deny)
        let tool = SearchCurrentBookTool(
            search: search,
            bookFingerprint: current,
            authorizationGate: AIAgentToolExecutionGate(
                preferencesStore: store, broker: broker,
                confirmationAvailability: .brokerConnected
            ),
            readerContext: makeContext(fingerprint: current)
        )
        let result = await tool.run(.object(["query": .string("needle")]))
        await resolver.value
        #expect(result.isError)
        #expect(await search.calls == 0)
    }

    @Test("search_current_book Ask approval executes once")
    @MainActor
    func currentSearchAskApproval() async {
        let store = WI6PreferencesStore(WI6Fixtures.preferences([.readCurrentBook: .ask]))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let search = WI6SearchSpy()
        let resolver = resolveNextWI6Confirmation(on: broker, with: .allowOnce)
        let tool = SearchCurrentBookTool(
            search: search,
            bookFingerprint: current,
            authorizationGate: AIAgentToolExecutionGate(
                preferencesStore: store, broker: broker,
                confirmationAvailability: .brokerConnected
            ),
            readerContext: makeContext(fingerprint: current)
        )
        let result = await tool.run(.object(["query": .string("needle")]))
        await resolver.value
        #expect(!result.isError)
        #expect(await search.calls == 1)
    }

    @Test("production-unavailable Ask fails closed without pending forever")
    @MainActor
    func askUnavailableFailsClosed() async {
        let store = WI6PreferencesStore(WI6Fixtures.preferences([.readCurrentBook: .ask]))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let search = WI6SearchSpy()
        let tool = SearchCurrentBookTool(
            search: search,
            bookFingerprint: current,
            authorizationGate: AIAgentToolExecutionGate(
                preferencesStore: store, broker: broker,
                confirmationAvailability: .unavailable
            ),
            readerContext: makeContext(fingerprint: current)
        )
        let result = await tool.run(.object(["query": .string("needle")]))
        #expect(result.isError)
        #expect(result.content.localizedCaseInsensitiveContains("approval"))
        #expect(await broker.pendingRequestCount == 0)
        #expect(await search.calls == 0)
    }

    @Test("cancelling a pending Ask prevents later backend execution")
    @MainActor
    func cancellationStopsCurrentSearch() async {
        let store = WI6PreferencesStore(WI6Fixtures.preferences([.readCurrentBook: .ask]))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let search = WI6SearchSpy()
        let tool = SearchCurrentBookTool(
            search: search,
            bookFingerprint: current,
            authorizationGate: AIAgentToolExecutionGate(
                preferencesStore: store, broker: broker,
                confirmationAvailability: .brokerConnected
            ),
            readerContext: makeContext(fingerprint: current)
        )
        let task = Task { await tool.run(.object(["query": .string("needle")])) }
        var iterator = await broker.pendingRequestUpdates().makeAsyncIterator()
        while let requests = await iterator.next(), requests.isEmpty {}
        task.cancel()
        let result = await task.value
        #expect(result.isError)
        #expect(await search.calls == 0)
    }

    @Test("search_other_books and list_library enforce readOtherBooks before listing")
    func otherBookToolsDenyBeforeListing() async {
        let backend = WI6LibrarySpy(books: [
            .stub(fingerprintKey: other.canonicalKey, title: "Secret title", format: "epub")
        ])
        let gate = WI6Fixtures.gate([.readOtherBooks: .deny])
        let searchResult = await SearchOtherBooksTool(
            backend: backend,
            currentBookFingerprintKey: current.canonicalKey,
            authorizationGate: gate
        ).run(.object(["query": .string("needle")]))
        let listResult = await ListLibraryTool(
            backend: backend,
            currentBookFingerprintKey: current.canonicalKey,
            authorizationGate: gate
        ).run(.object([:]))
        #expect(searchResult.isError && listResult.isError)
        #expect(!searchResult.content.contains("Secret title"))
        #expect(!listResult.content.contains("Secret title"))
        #expect(await backend.listCalls == 0)
    }

    @Test("get_book_content selects current versus other permission categories")
    @MainActor
    func contentUsesTargetIdentityPermission() async {
        let currentProvider = WI6ContentSpy(resolution: .found(BookContentInfo(
            fingerprintKey: current.canonicalKey, title: "Current", isReadable: true
        )))
        let currentTool = GetBookContentTool(
            provider: currentProvider,
            authorizationGate: WI6Fixtures.gate([
                .readCurrentBook: .deny, .readOtherBooks: .allow
            ]),
            readerContext: makeContext(fingerprint: current, title: "Current")
        )
        let currentResult = await currentTool.run(.object(["title": .string("Current")]))
        #expect(currentResult.isError)
        #expect(await currentProvider.extractionCalls == 0)

        let otherProvider = WI6ContentSpy(resolution: .found(BookContentInfo(
            fingerprintKey: other.canonicalKey, title: "Other", isReadable: true
        )))
        let otherTool = GetBookContentTool(
            provider: otherProvider,
            authorizationGate: WI6Fixtures.gate([
                .readCurrentBook: .allow, .readOtherBooks: .deny
            ]),
            readerContext: makeContext(fingerprint: current, title: "Current")
        )
        let otherResult = await otherTool.run(.object(["title": .string("Other")]))
        #expect(otherResult.isError)
        #expect(await otherProvider.extractionCalls == 0)
    }

    @MainActor
    private func makeContext(
        fingerprint: DocumentFingerprint,
        title: String = "Current"
    ) -> AILiveReaderToolContext {
        let text = "0123456789"
        let chunk = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "\(fingerprint.format.rawValue):segment:0",
            index: 0, text: text, local: 0..<10, global: 0..<10
        )
        let provider = WI6DocumentProvider(
            fingerprint: fingerprint,
            chunks: [chunk],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fingerprint, current: chunk,
                localBoundary: 10, globalBoundary: 10
            )
        )
        let registry = AIDocumentProviderRegistry()
        let token = UUID()
        registry.attach(provider, for: AIDocumentSessionID(
            fingerprintKey: fingerprint.canonicalKey, readerToken: token
        ))
        return AILiveReaderToolContext(
            bookTitle: title,
            fingerprint: fingerprint,
            readerToken: token,
            providerResolver: registry
        )
    }
}
