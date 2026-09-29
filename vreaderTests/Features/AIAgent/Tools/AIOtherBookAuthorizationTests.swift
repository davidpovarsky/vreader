// Purpose: Existing other-book search/list authorization contracts for WI-6.

import Foundation
import Testing
@testable import vreader

private actor WI6OtherBookBackend: LibrarySearchBackend {
    let fingerprint: DocumentFingerprint
    private(set) var listCalls = 0
    private(set) var searchCalls = 0

    init(fingerprint: DocumentFingerprint) {
        self.fingerprint = fingerprint
    }

    func libraryBooks() async throws -> [LibraryBookItem] {
        listCalls += 1
        return [.stub(
            fingerprintKey: fingerprint.canonicalKey,
            title: "Protected Other", format: fingerprint.format.rawValue
        )]
    }

    func indexState(fingerprintKey: String) async -> LibraryIndexState {
        LibraryIndexState(isIndexed: true, requiresReindex: false, segmentOffsets: nil)
    }

    func restoreSegmentOffsets(
        fingerprint: DocumentFingerprint,
        offsets: [Int: Int]
    ) async {}

    func search(
        query: String,
        fingerprint: DocumentFingerprint,
        limit: Int
    ) async throws -> SearchResultPage {
        searchCalls += 1
        return SearchResultPage(
            results: [SearchResult(
                id: "other-hit", snippet: "protected hit",
                locator: WI6Fixtures.locator(fingerprint: fingerprint, href: "chapter.xhtml"),
                sourceContext: "Chapter"
            )],
            page: 0, hasMore: false, totalEstimate: 1
        )
    }
}

@Suite("Feature #177 WI-6 — other-book authorization")
struct AIOtherBookAuthorizationTests {
    @Test("readOtherBooks Allow preserves search and list behavior")
    func allowExecutesBothBackends() async {
        let fingerprint = WI6Fixtures.fingerprint("7", format: .epub)
        let backend = WI6OtherBookBackend(fingerprint: fingerprint)
        let gate = WI6Fixtures.gate([.readOtherBooks: .allow])

        let search = await SearchOtherBooksTool(
            backend: backend, currentBookFingerprintKey: nil,
            authorizationGate: gate
        ).run(.object(["query": .string("protected")]))
        let list = await ListLibraryTool(
            backend: backend, currentBookFingerprintKey: nil,
            authorizationGate: gate
        ).run(.object([:]))

        #expect(search.content.contains("protected hit"))
        #expect(list.content.contains("Protected Other"))
        #expect(await backend.listCalls == 2)
        #expect(await backend.searchCalls == 1)
    }

    @Test("readOtherBooks Ask denial prevents other-book search")
    func askDenialStopsSearch() async {
        let fingerprint = WI6Fixtures.fingerprint("8", format: .epub)
        let backend = WI6OtherBookBackend(fingerprint: fingerprint)
        let store = WI6PreferencesStore(WI6Fixtures.preferences([.readOtherBooks: .ask]))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let resolver = resolveNextWI6Confirmation(on: broker, with: .deny)

        let result = await SearchOtherBooksTool(
            backend: backend, currentBookFingerprintKey: nil,
            authorizationGate: AIAgentToolExecutionGate(
                preferencesStore: store, broker: broker,
                confirmationAvailability: .brokerConnected
            )
        ).run(.object(["query": .string("protected")]))
        await resolver.value

        #expect(result.isError)
        #expect(!result.content.contains("Protected Other"))
        #expect(await backend.listCalls == 0)
        #expect(await backend.searchCalls == 0)
    }
}
