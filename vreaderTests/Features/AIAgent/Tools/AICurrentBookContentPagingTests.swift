// Purpose: Regression contract proving current-book paging cannot bypass WI-6 boundaries.

import Foundation
import Testing
@testable import vreader

@Suite("Feature #177 WI-6 — current-book content paging")
struct AICurrentBookContentPagingTests {
    @Test("get_book_content pages only inside the spoiler-safe structured payload")
    @MainActor
    func contentPagingCannotJumpPastBoundary() async {
        let fingerprint = WI6Fixtures.fingerprint("3", format: .txt)
        let chunk = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "txt:segment:0", index: 0,
            text: "SAFE-FUTURE", local: 0..<11, global: 0..<11
        )
        let context = makeContext(
            fingerprint: fingerprint,
            chunks: [chunk],
            snapshot: WI6Fixtures.snapshot(
                fingerprint: fingerprint, current: chunk,
                localBoundary: 4, globalBoundary: 4
            )
        )
        let provider = WI6FixedContentProvider(
            fingerprint: fingerprint,
            flattened: "WRONG-FLATTENED-FUTURE"
        )
        let tool = GetBookContentTool(
            provider: provider,
            authorizationGate: WI6Fixtures.gate([
                .readCurrentBook: .allow, .readAhead: .allow,
            ], readAhead: .neverReadAhead),
            readerContext: context
        )
        let result = await tool.run(.object([
            "title": .string("Current"),
            "start_char": .number(1_000_000),
        ]))

        #expect(result.isError)
        #expect(!result.content.contains("FUTURE"))
        #expect(await provider.extractionCalls == 0)
    }

    @MainActor
    private func makeContext(
        fingerprint: DocumentFingerprint,
        chunks: [AIDocumentChunk],
        snapshot: AIDocumentSnapshot
    ) -> AILiveReaderToolContext {
        let provider = WI6DocumentProvider(
            fingerprint: fingerprint, chunks: chunks, snapshot: snapshot
        )
        let registry = AIDocumentProviderRegistry()
        let token = UUID()
        registry.attach(provider, for: AIDocumentSessionID(
            fingerprintKey: fingerprint.canonicalKey, readerToken: token
        ))
        return AILiveReaderToolContext(
            bookTitle: "Current", fingerprint: fingerprint,
            readerToken: token, providerResolver: registry
        )
    }
}

private actor WI6FixedContentProvider: BookContentProvider {
    let fingerprint: DocumentFingerprint
    let flattened: String
    private(set) var extractionCalls = 0

    init(fingerprint: DocumentFingerprint, flattened: String) {
        self.fingerprint = fingerprint
        self.flattened = flattened
    }

    func findBook(title: String) async -> BookTitleResolution {
        .found(BookContentInfo(
            fingerprintKey: fingerprint.canonicalKey,
            title: "Current",
            isReadable: true
        ))
    }

    func extractText(fingerprintKey: String) async throws -> String {
        extractionCalls += 1
        return flattened
    }
}
