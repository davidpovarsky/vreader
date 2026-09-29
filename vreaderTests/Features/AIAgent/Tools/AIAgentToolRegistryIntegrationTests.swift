// Purpose: Feature #177 WI-6 RED contracts for production registry composition.

import Foundation
import Testing
@testable import vreader

private struct WI6EmptyLibrary: LibrarySearchBackend {
    func libraryBooks() async throws -> [LibraryBookItem] { [] }
    func indexState(fingerprintKey: String) async -> LibraryIndexState {
        LibraryIndexState(isIndexed: false, requiresReindex: false, segmentOffsets: nil)
    }
    func restoreSegmentOffsets(fingerprint: DocumentFingerprint, offsets: [Int: Int]) async {}
    func search(
        query: String, fingerprint: DocumentFingerprint, limit: Int
    ) async throws -> SearchResultPage {
        SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
    }
}

private struct WI6EmptyContent: BookContentProvider {
    func findBook(title: String) async -> BookTitleResolution { .notFound }
    func extractText(fingerprintKey: String) async throws -> String { "" }
}

private struct WI6EmptyAnnotations: AIAnnotationReading {
    func readAnnotations(fingerprintKey: String) async throws -> AIAnnotationCollection {
        AIAnnotationCollection(notes: [], highlights: [], bookmarks: [])
    }
}

private struct WI6EmptySearch: SearchProviding {
    func indexBook(
        fingerprint: DocumentFingerprint, textUnits: [TextUnit],
        segmentBaseOffsets: [Int: Int]?
    ) async throws {}
    func search(
        query: String, bookFingerprint: DocumentFingerprint,
        page: Int, pageSize: Int
    ) async throws -> SearchResultPage {
        SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
    }
    func removeIndex(fingerprint: DocumentFingerprint) async throws {}
    func isIndexed(fingerprint: DocumentFingerprint) async -> Bool { true }
}

@Suite("Feature #177 WI-6 — agent tool registry integration")
struct AIAgentToolRegistryIntegrationTests {
    @Test("reader chat registers lexical, reader, annotation, and navigation tools")
    @MainActor
    func readerRegistryIncludesWI6Tools() {
        let fixture = makeReader()
        let registry = AgenticToolRegistryBuilder.build(
            currentBook: fixture.fingerprint,
            currentBookSearch: WI6EmptySearch(),
            libraryBackend: WI6EmptyLibrary(),
            contentProvider: WI6EmptyContent(),
            authorizationGate: WI6Fixtures.gate([
                .readCurrentBook: .allow, .readOtherBooks: .allow,
                .navigateReader: .allow, .readAhead: .allow
            ]),
            readerContext: fixture.context,
            annotationStore: WI6EmptyAnnotations(),
            navigationRouter: WI6NavigationSpy()
        )
        #expect(Set(registry.definitions().map(\.name)) == Set([
            "search_current_book", "search_other_books", "get_book_content", "list_library",
            "get_current_location", "get_current_context", "get_current_chapter",
            "get_table_of_contents", "search_annotations", "get_annotations",
            "open_location", "open_book",
        ]))
    }

    @Test("general chat excludes every exact-reader-only tool")
    func generalRegistryOmitsReaderTools() {
        let registry = AgenticToolRegistryBuilder.build(
            currentBook: nil,
            currentBookSearch: nil,
            libraryBackend: WI6EmptyLibrary(),
            contentProvider: WI6EmptyContent(),
            authorizationGate: WI6Fixtures.gate([.readOtherBooks: .allow])
        )
        let names = Set(registry.definitions().map(\.name))
        #expect(names.isSuperset(of: [
            "search_other_books", "get_book_content", "list_library"
        ]))
        #expect(names.isDisjoint(with: [
            "search_current_book", "get_current_location", "get_current_context",
            "get_current_chapter", "get_table_of_contents", "open_location"
        ]))
    }

    @Test("assembled library tools use WI-5 authorization")
    func registryLibraryToolIsAuthorizationGated() async {
        let backend = WI6CountingLibrary()
        let registry = AgenticToolRegistryBuilder.build(
            currentBook: nil,
            currentBookSearch: nil,
            libraryBackend: backend,
            contentProvider: WI6EmptyContent(),
            authorizationGate: WI6Fixtures.gate([.readOtherBooks: .deny])
        )
        let result = await registry.run(ToolCall(
            id: "list", name: "list_library", input: .object([:])
        ))
        #expect(result.isError)
        #expect(await backend.calls == 0)
    }

    @Test("two same-book registries keep exact reader contexts isolated")
    @MainActor
    func sameBookRegistryIsolation() async {
        let fp = WI6Fixtures.fingerprint("f", format: .pdf)
        let registry = AIDocumentProviderRegistry()
        let a = makeReader(fingerprint: fp, page: 1, text: "READER-A", registry: registry)
        let b = makeReader(fingerprint: fp, page: 7, text: "READER-B", registry: registry)
        let toolRegistryA = makeRegistry(reader: a)
        let toolRegistryB = makeRegistry(reader: b)
        let resultA = await toolRegistryA.run(ToolCall(
            id: "a", name: "get_current_context", input: .object([:])
        ))
        let resultB = await toolRegistryB.run(ToolCall(
            id: "b", name: "get_current_context", input: .object([:])
        ))
        #expect(resultA.content.contains("READER-A"))
        #expect(!resultA.content.contains("READER-B"))
        #expect(resultB.content.contains("READER-B"))
        #expect(!resultB.content.contains("READER-A"))
    }

    @MainActor
    private func makeRegistry(
        reader: (fingerprint: DocumentFingerprint, context: AILiveReaderToolContext)
    ) -> AIToolRegistry {
        AgenticToolRegistryBuilder.build(
            currentBook: reader.fingerprint,
            currentBookSearch: WI6EmptySearch(),
            libraryBackend: WI6EmptyLibrary(),
            contentProvider: WI6EmptyContent(),
            authorizationGate: WI6Fixtures.gate([
                .readCurrentBook: .allow, .readOtherBooks: .allow,
                .navigateReader: .allow, .readAhead: .allow
            ], readAhead: .wholeBookAllowed),
            readerContext: reader.context,
            annotationStore: WI6EmptyAnnotations(),
            navigationRouter: WI6NavigationSpy()
        )
    }

    @MainActor
    private func makeReader() -> (
        fingerprint: DocumentFingerprint,
        context: AILiveReaderToolContext
    ) {
        makeReader(
            fingerprint: WI6Fixtures.fingerprint("a", format: .pdf),
            page: 2, text: "PAGE", registry: AIDocumentProviderRegistry()
        )
    }

    @MainActor
    private func makeReader(
        fingerprint: DocumentFingerprint,
        page: Int,
        text: String,
        registry: AIDocumentProviderRegistry
    ) -> (fingerprint: DocumentFingerprint, context: AILiveReaderToolContext) {
        let chunk = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "pdf:page:\(page)", index: page,
            text: text, page: page, local: 0..<text.utf16.count
        )
        let token = UUID()
        registry.attach(WI6DocumentProvider(
            fingerprint: fingerprint, chunks: [chunk],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fingerprint, current: chunk,
                localBoundary: text.utf16.count
            )
        ), for: AIDocumentSessionID(
            fingerprintKey: fingerprint.canonicalKey, readerToken: token
        ))
        return (
            fingerprint,
            AILiveReaderToolContext(
                bookTitle: "Book", fingerprint: fingerprint,
                readerToken: token, providerResolver: registry
            )
        )
    }
}

private actor WI6CountingLibrary: LibrarySearchBackend {
    private(set) var calls = 0
    func libraryBooks() async throws -> [LibraryBookItem] {
        calls += 1
        return []
    }
    func indexState(fingerprintKey: String) async -> LibraryIndexState {
        LibraryIndexState(isIndexed: false, requiresReindex: false, segmentOffsets: nil)
    }
    func restoreSegmentOffsets(fingerprint: DocumentFingerprint, offsets: [Int: Int]) async {}
    func search(
        query: String, fingerprint: DocumentFingerprint, limit: Int
    ) async throws -> SearchResultPage {
        SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
    }
}
