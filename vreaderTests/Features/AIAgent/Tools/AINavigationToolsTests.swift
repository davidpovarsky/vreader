// Purpose: Feature #177 WI-6 RED contracts for reader navigation tools.

import Foundation
import Testing
@testable import vreader

actor WI6NavigationSpy: AIReaderNavigationRouting {
    private(set) var locations: [(Locator, AIDocumentSessionID)] = []
    private(set) var opened: [(String, Locator?)] = []

    func navigate(to locator: Locator, session: AIDocumentSessionID) async -> Bool {
        guard !Task.isCancelled else { return false }
        locations.append((locator, session))
        return true
    }

    func openBook(fingerprintKey: String, locator: Locator?) async -> Bool {
        guard !Task.isCancelled else { return false }
        opened.append((fingerprintKey, locator))
        return true
    }
}

@Suite("Feature #177 WI-6 — navigation tools")
struct AINavigationToolsTests {
    @Test("open_location Allow navigates exact current session once")
    @MainActor
    func locationAllowNavigatesOnce() async {
        let fixture = makeContext()
        let spy = WI6NavigationSpy()
        let result = await OpenLocationTool(
            context: fixture.context,
            router: spy,
            authorizationGate: WI6Fixtures.gate([.navigateReader: .allow])
        ).run(locatorInput(fixture.locator))
        #expect(!result.isError)
        #expect(await spy.locations.count == 1)
        #expect(await spy.locations.first?.1 == fixture.context.sessionID)
    }

    @Test("open_location Deny and Ask denial cause zero navigation")
    @MainActor
    func locationDeniedHasNoSideEffect() async {
        let fixture = makeContext()
        let spy = WI6NavigationSpy()
        let denied = await OpenLocationTool(
            context: fixture.context, router: spy,
            authorizationGate: WI6Fixtures.gate([.navigateReader: .deny])
        ).run(locatorInput(fixture.locator))
        #expect(denied.isError)

        let store = WI6PreferencesStore(WI6Fixtures.preferences([.navigateReader: .ask]))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let resolver = resolveNextWI6Confirmation(on: broker, with: .deny)
        let asked = await OpenLocationTool(
            context: fixture.context, router: spy,
            authorizationGate: AIAgentToolExecutionGate(
                preferencesStore: store, broker: broker,
                confirmationAvailability: .brokerConnected
            )
        ).run(locatorInput(fixture.locator))
        await resolver.value
        #expect(asked.isError)
        #expect(await spy.locations.isEmpty)
    }

    @Test("open_location rejects wrong-book locator without cross-wire")
    @MainActor
    func locationRejectsWrongBook() async {
        let fixture = makeContext()
        let wrong = WI6Fixtures.locator(
            fingerprint: WI6Fixtures.fingerprint("b", format: .pdf), page: 2
        )
        let spy = WI6NavigationSpy()
        let result = await OpenLocationTool(
            context: fixture.context, router: spy,
            authorizationGate: WI6Fixtures.gate([.navigateReader: .allow])
        ).run(locatorInput(wrong))
        #expect(result.isError)
        #expect(result.content.contains("open_book"))
        #expect(await spy.locations.isEmpty)
    }

    @Test("cancelled open_location cannot navigate later")
    @MainActor
    func cancelledLocationDoesNotNavigate() async {
        let fixture = makeContext()
        let spy = WI6NavigationSpy()
        let store = WI6PreferencesStore(WI6Fixtures.preferences([.navigateReader: .ask]))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let tool = OpenLocationTool(
            context: fixture.context, router: spy,
            authorizationGate: AIAgentToolExecutionGate(
                preferencesStore: store, broker: broker,
                confirmationAvailability: .brokerConnected
            )
        )
        let task = Task { await tool.run(locatorInput(fixture.locator)) }
        var iterator = await broker.pendingRequestUpdates().makeAsyncIterator()
        while let requests = await iterator.next(), requests.isEmpty {}
        task.cancel()
        _ = await task.value
        #expect(await spy.locations.isEmpty)
    }

    @Test("open_book requires readOtherBooks and navigateReader before opening")
    @MainActor
    func openBookRequiresBothCategories() async {
        let fixture = makeContext()
        let other = WI6Fixtures.fingerprint("c", format: .epub)
        let resolver = WI6BookResolver(books: [
            "Other": BookContentInfo(
                fingerprintKey: other.canonicalKey, title: "Other", isReadable: true
            )
        ])
        let spy = WI6NavigationSpy()
        let readDenied = await OpenBookTool(
            bookResolver: resolver, router: spy,
            authorizationGate: WI6Fixtures.gate([
                .readOtherBooks: .deny, .navigateReader: .allow
            ])
        ).run(.object(["title": .string("Other")]))
        #expect(readDenied.isError)

        let navigateDenied = await OpenBookTool(
            bookResolver: resolver, router: spy,
            authorizationGate: WI6Fixtures.gate([
                .readOtherBooks: .allow, .navigateReader: .deny
            ])
        ).run(.object(["title": .string("Other")]))
        #expect(navigateDenied.isError)
        #expect(await spy.opened.isEmpty)
        _ = fixture
    }

    @Test("open_book success opens once and carries optional target locator")
    @MainActor
    func openBookOnceWithTarget() async {
        let other = WI6Fixtures.fingerprint("d", format: .epub)
        let target = WI6Fixtures.locator(fingerprint: other, href: "chapter-4.xhtml")
        let resolver = WI6BookResolver(books: [
            "Other": BookContentInfo(
                fingerprintKey: other.canonicalKey, title: "Other", isReadable: true
            )
        ])
        let spy = WI6NavigationSpy()
        let result = await OpenBookTool(
            bookResolver: resolver, router: spy,
            authorizationGate: WI6Fixtures.gate([
                .readOtherBooks: .allow, .navigateReader: .allow
            ])
        ).run(.object([
            "title": .string("Other"),
            "locator_json": .string(try! AIReaderToolOutput.encode(target))
        ]))
        #expect(!result.isError)
        #expect(await spy.opened.count == 1)
        #expect(await spy.opened.first?.0 == other.canonicalKey)
        #expect(await spy.opened.first?.1 == target)
    }

    @Test("open_book rejects target locator for another resolved book")
    func openBookRejectsMismatchedTarget() async {
        let other = WI6Fixtures.fingerprint("e", format: .epub)
        let wrong = WI6Fixtures.locator(
            fingerprint: WI6Fixtures.fingerprint("f", format: .pdf), page: 1
        )
        let spy = WI6NavigationSpy()
        let result = await OpenBookTool(
            bookResolver: WI6BookResolver(books: [
                "Other": BookContentInfo(
                    fingerprintKey: other.canonicalKey, title: "Other", isReadable: true
                )
            ]),
            router: spy,
            authorizationGate: WI6Fixtures.gate([
                .readOtherBooks: .allow, .navigateReader: .allow
            ])
        ).run(.object([
            "title": .string("Other"),
            "locator_json": .string(try! AIReaderToolOutput.encode(wrong))
        ]))
        #expect(result.isError)
        #expect(await spy.opened.isEmpty)
    }

    @Test("cancelled open_book Ask cannot perform a delayed open")
    func cancelledOpenBookDoesNotOpen() async {
        let other = WI6Fixtures.fingerprint("7", format: .epub)
        let store = WI6PreferencesStore(WI6Fixtures.preferences([
            .readOtherBooks: .ask, .navigateReader: .allow,
        ]))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let spy = WI6NavigationSpy()
        let tool = OpenBookTool(
            bookResolver: WI6BookResolver(books: [
                "Other": BookContentInfo(
                    fingerprintKey: other.canonicalKey,
                    title: "Other", isReadable: true
                ),
            ]),
            router: spy,
            authorizationGate: AIAgentToolExecutionGate(
                preferencesStore: store, broker: broker,
                confirmationAvailability: .brokerConnected
            )
        )
        let task = Task { await tool.run(.object(["title": .string("Other")])) }
        var iterator = await broker.pendingRequestUpdates().makeAsyncIterator()
        while let requests = await iterator.next(), requests.isEmpty {}
        task.cancel()
        _ = await task.value
        #expect(await spy.opened.isEmpty)
    }

    @Test("duplicate confirmation resolution cannot duplicate an open")
    func duplicateResolutionOpensOnce() async {
        let other = WI6Fixtures.fingerprint("8", format: .epub)
        let store = WI6PreferencesStore(WI6Fixtures.preferences([
            .readOtherBooks: .ask, .navigateReader: .ask,
        ]))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let spy = WI6NavigationSpy()
        let task = Task {
            await OpenBookTool(
                bookResolver: WI6BookResolver(books: [
                    "Other": BookContentInfo(
                        fingerprintKey: other.canonicalKey,
                        title: "Other", isReadable: true
                    ),
                ]),
                router: spy,
                authorizationGate: AIAgentToolExecutionGate(
                    preferencesStore: store, broker: broker,
                    confirmationAvailability: .brokerConnected
                )
            ).run(.object(["title": .string("Other")]))
        }
        var iterator = await broker.pendingRequestUpdates().makeAsyncIterator()
        var resolvedIDs: [UUID] = []
        while resolvedIDs.count < 2, let requests = await iterator.next() {
            guard let request = requests.first,
                  !resolvedIDs.contains(request.id) else { continue }
            resolvedIDs.append(request.id)
            #expect(await broker.resolve(request.id, with: .allowOnce))
            #expect(!(await broker.resolve(request.id, with: .allowOnce)))
        }
        let result = await task.value
        #expect(!result.isError)
        #expect(await spy.opened.count == 1)
    }

    @MainActor
    private func makeContext() -> (
        context: AILiveReaderToolContext,
        locator: Locator
    ) {
        let fp = WI6Fixtures.fingerprint("a", format: .pdf)
        let chunk = WI6Fixtures.chunk(
            fingerprint: fp, id: "pdf:page:1", index: 1,
            text: "page", page: 1, local: 0..<4
        )
        let registry = AIDocumentProviderRegistry()
        let token = UUID()
        registry.attach(WI6DocumentProvider(
            fingerprint: fp, chunks: [chunk],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fp, current: chunk, localBoundary: 4
            )
        ), for: AIDocumentSessionID(
            fingerprintKey: fp.canonicalKey, readerToken: token
        ))
        return (
            AILiveReaderToolContext(
                bookTitle: "Current", fingerprint: fp,
                readerToken: token, providerResolver: registry
            ),
            chunk.locator
        )
    }

    private func locatorInput(_ locator: Locator) -> JSONValue {
        .object(["locator_json": .string(try! AIReaderToolOutput.encode(locator))])
    }
}
