// Purpose: Feature #177 WI-6 RED contracts for read-only annotation tools.

import Foundation
import Testing
@testable import vreader

private actor WI6AnnotationStore: AIAnnotationReading {
    var values: [String: AIAnnotationCollection]
    private(set) var readKeys: [String] = []
    private(set) var mutationCount = 0

    init(values: [String: AIAnnotationCollection]) { self.values = values }

    func readAnnotations(fingerprintKey: String) async throws -> AIAnnotationCollection {
        readKeys.append(fingerprintKey)
        return values[fingerprintKey] ?? AIAnnotationCollection(
            notes: [], highlights: [], bookmarks: []
        )
    }
}

struct WI6BookResolver: BookContentProvider {
    let books: [String: BookContentInfo]

    func findBook(title: String) async -> BookTitleResolution {
        books[title].map(BookTitleResolution.found) ?? .notFound
    }

    func extractText(fingerprintKey: String) async throws -> String { "" }
}

@Suite("Feature #177 WI-6 — annotation read tools")
struct AIAnnotationReadToolsTests {
    @Test("search_annotations finds current-book note and retains locator identity")
    @MainActor
    func searchesCurrentAnnotations() async {
        let fixture = makeFixture()
        let result = await SearchAnnotationsTool(
            store: fixture.store,
            bookResolver: fixture.resolver,
            readerContext: fixture.context,
            authorizationGate: allowCurrentNeverGate()
        ).run(.object(["query": .string("dragon")]))
        #expect(!result.isError)
        #expect(result.content.contains("dragon note"))
        let noteLine = result.content
            .components(separatedBy: .newlines)
            .first { $0.contains("dragon note") } ?? ""
        guard let markerRange = noteLine.range(of: "locator_json=") else {
            Issue.record("Missing locator_json in output line: \(noteLine)")
            return
        }
        let rawLocatorJSON = String(noteLine[markerRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let locator = AIReaderToolOutput.decodeLocator(.object(["locator_json": .string(rawLocatorJSON)]))
        #expect(locator != nil)
        #expect(locator?.bookFingerprint == fixture.current)
        #expect(locator?.charOffsetUTF16 == 10)
    }

    @Test("annotation query is strict and empty input performs no read")
    @MainActor
    func rejectsBlankQuery() async {
        let fixture = makeFixture()
        let result = await SearchAnnotationsTool(
            store: fixture.store,
            bookResolver: fixture.resolver,
            readerContext: fixture.context,
            authorizationGate: allowCurrentNeverGate()
        ).run(.object(["query": .string("  ")]))
        #expect(result.isError)
        #expect(await fixture.store.readKeys.isEmpty)
    }

    @Test("bounded annotation count and text are reported deterministically")
    @MainActor
    func boundedResults() async {
        let fixture = makeFixture(many: true)
        let result = await GetAnnotationsTool(
            store: fixture.store,
            bookResolver: fixture.resolver,
            readerContext: fixture.context,
            authorizationGate: allowCurrentNeverGate(),
            maxResults: 2,
            maxTextCharacters: 24
        ).run(.object([:]))
        #expect(!result.isError)
        #expect(result.content.contains("Showing 2 of"))
        #expect(!result.content.contains(String(repeating: "z", count: 25)))
    }

    @Test("future current-book annotation is hidden under Never")
    @MainActor
    func hidesFutureAnnotation() async {
        let fixture = makeFixture()
        let result = await GetAnnotationsTool(
            store: fixture.store,
            bookResolver: fixture.resolver,
            readerContext: fixture.context,
            authorizationGate: allowCurrentNeverGate()
        ).run(.object([:]))
        #expect(result.content.contains("dragon note"))
        #expect(!result.content.contains("future secret"))
    }

    @Test("Ask denial does not expose future annotation")
    @MainActor
    func askDenialHidesFuture() async {
        let fixture = makeFixture()
        let store = WI6PreferencesStore(WI6Fixtures.preferences(
            [.readCurrentBook: .allow, .readAhead: .allow],
            readAhead: .askBeforeReadingAhead
        ))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let resolver = resolveNextWI6Confirmation(on: broker, with: .deny)
        let result = await GetAnnotationsTool(
            store: fixture.store,
            bookResolver: fixture.resolver,
            readerContext: fixture.context,
            authorizationGate: AIAgentToolExecutionGate(
                preferencesStore: store, broker: broker,
                confirmationAvailability: .brokerConnected
            )
        ).run(.object([:]))
        await resolver.value
        #expect(!result.content.contains("future secret"))
    }

    @Test("other-book annotations require readOtherBooks and do not use current boundary")
    @MainActor
    func otherBookPermission() async {
        let fixture = makeFixture()
        let denied = await GetAnnotationsTool(
            store: fixture.store,
            bookResolver: fixture.resolver,
            readerContext: fixture.context,
            authorizationGate: WI6Fixtures.gate([
                .readCurrentBook: .allow, .readOtherBooks: .deny
            ])
        ).run(.object(["book_title": .string("Other")]))
        #expect(denied.isError)
        #expect(!denied.content.contains("other annotation"))

        let allowed = await GetAnnotationsTool(
            store: fixture.store,
            bookResolver: fixture.resolver,
            readerContext: fixture.context,
            authorizationGate: WI6Fixtures.gate([.readOtherBooks: .allow])
        ).run(.object(["book_title": .string("Other")]))
        #expect(!allowed.isError)
        #expect(allowed.content.contains("other annotation"))
    }

    @Test("annotation tools perform no mutation")
    @MainActor
    func readOnly() async {
        let fixture = makeFixture()
        _ = await GetAnnotationsTool(
            store: fixture.store,
            bookResolver: fixture.resolver,
            readerContext: fixture.context,
            authorizationGate: allowCurrentNeverGate()
        ).run(.object([:]))
        _ = await SearchAnnotationsTool(
            store: fixture.store,
            bookResolver: fixture.resolver,
            readerContext: fixture.context,
            authorizationGate: allowCurrentNeverGate()
        ).run(.object(["query": .string("dragon")]))
        #expect(await fixture.store.mutationCount == 0)
    }

    @MainActor
    private func makeFixture(many: Bool = false) -> (
        current: DocumentFingerprint,
        context: AILiveReaderToolContext,
        store: WI6AnnotationStore,
        resolver: WI6BookResolver
    ) {
        let current = WI6Fixtures.fingerprint("a", format: .txt)
        let other = WI6Fixtures.fingerprint("b", format: .epub)
        let document = WI6Fixtures.chunk(
            fingerprint: current, id: "txt:segment:0", index: 0,
            text: String(repeating: "x", count: 100),
            local: 0..<100, global: 0..<100
        )
        let registry = AIDocumentProviderRegistry()
        let token = UUID()
        registry.attach(WI6DocumentProvider(
            fingerprint: current,
            chunks: [document],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: current, current: document,
                localBoundary: 50, globalBoundary: 50
            )
        ), for: AIDocumentSessionID(
            fingerprintKey: current.canonicalKey, readerToken: token
        ))
        let context = AILiveReaderToolContext(
            bookTitle: "Current", fingerprint: current,
            readerToken: token, providerResolver: registry
        )
        var notes = [AnnotationRecord(
            annotationId: UUID(),
            locator: WI6Fixtures.locator(fingerprint: current, offset: 10),
            profileKey: "default", content: "dragon note",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        ), AnnotationRecord(
            annotationId: UUID(),
            locator: WI6Fixtures.locator(fingerprint: current, offset: 80),
            profileKey: "default", content: "future secret",
            createdAt: Date(timeIntervalSince1970: 2),
            updatedAt: Date(timeIntervalSince1970: 2)
        )]
        if many {
            notes += (0..<5).map { index in
                AnnotationRecord(
                    annotationId: UUID(),
                    locator: WI6Fixtures.locator(fingerprint: current, offset: index),
                    profileKey: "default",
                    content: "\(index)-" + String(repeating: "z", count: 100),
                    createdAt: Date(timeIntervalSince1970: Double(10 + index)),
                    updatedAt: Date(timeIntervalSince1970: Double(10 + index))
                )
            }
        }
        let otherNote = AnnotationRecord(
            annotationId: UUID(),
            locator: WI6Fixtures.locator(fingerprint: other, href: "chapter.xhtml"),
            profileKey: "default", content: "other annotation",
            createdAt: .distantPast, updatedAt: .distantPast
        )
        return (
            current,
            context,
            WI6AnnotationStore(values: [
                current.canonicalKey: AIAnnotationCollection(
                    notes: notes, highlights: [], bookmarks: []
                ),
                other.canonicalKey: AIAnnotationCollection(
                    notes: [otherNote], highlights: [], bookmarks: []
                ),
            ]),
            WI6BookResolver(books: [
                "Current": BookContentInfo(
                    fingerprintKey: current.canonicalKey, title: "Current", isReadable: true
                ),
                "Other": BookContentInfo(
                    fingerprintKey: other.canonicalKey, title: "Other", isReadable: true
                ),
            ])
        )
    }

    private func allowCurrentNeverGate() -> AIAgentToolExecutionGate {
        WI6Fixtures.gate([
            .readCurrentBook: .allow, .readAhead: .allow
        ], readAhead: .neverReadAhead)
    }
}
