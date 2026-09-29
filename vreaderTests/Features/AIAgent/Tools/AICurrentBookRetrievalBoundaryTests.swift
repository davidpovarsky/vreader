// Purpose: Feature #177 WI-6 RED contracts for spoiler-safe structured retrieval.

import Foundation
import Testing
@testable import vreader

@Suite("Feature #177 WI-6 — current-book retrieval boundary")
struct AICurrentBookRetrievalBoundaryTests {
    @Test("PDF later page is denied while the current page remains allowed")
    func pdfPageBoundary() async {
        let fp = WI6Fixtures.fingerprint("a", format: .pdf)
        let current = WI6Fixtures.chunk(
            fingerprint: fp, id: "pdf:page:2", index: 2,
            text: "current", page: 2, local: 0..<7
        )
        let future = WI6Fixtures.chunk(
            fingerprint: fp, id: "pdf:page:3", index: 3,
            text: "future", page: 3, local: 0..<6
        )
        let boundary = WI6Fixtures.snapshot(
            fingerprint: fp, current: current, localBoundary: 7
        ).readSoFarBoundary
        let coordinator = AICurrentBookRetrievalBoundary(
            authorizationGate: WI6Fixtures.gate(
                [.readAhead: .allow], readAhead: .neverReadAhead
            )
        )
        #expect(await coordinator.authorizedText(
            current, boundary: boundary, toolName: "test", actionDescription: "read"
        )?.text == "current")
        #expect(await coordinator.authorizedText(
            future, boundary: boundary, toolName: "test", actionDescription: "read"
        ) == nil)
    }

    @Test("EPUB later href is denied and unknown ordering fails closed")
    func epubResourceBoundary() async {
        let fp = WI6Fixtures.fingerprint("b", format: .epub)
        let current = WI6Fixtures.chunk(
            fingerprint: fp, id: "epub:one.xhtml", index: 0,
            text: "one", href: "one.xhtml", local: 0..<3
        )
        let later = WI6Fixtures.chunk(
            fingerprint: fp, id: "epub:two.xhtml", index: 1,
            text: "two", href: "two.xhtml", local: 0..<3
        )
        let unknown = WI6Fixtures.chunk(
            fingerprint: fp, id: "epub:mystery.xhtml", index: nil,
            text: "mystery", href: "mystery.xhtml", local: 0..<7
        )
        let boundary = WI6Fixtures.snapshot(
            fingerprint: fp, current: current, localBoundary: nil
        ).readSoFarBoundary
        let coordinator = neverCoordinator()
        #expect(await coordinator.authorizedText(
            later, boundary: boundary, toolName: "test", actionDescription: "read"
        ) == nil)
        #expect(await coordinator.authorizedText(
            unknown, boundary: boundary, toolName: "test", actionDescription: "read"
        ) == nil)
    }

    @Test("TXT exact range before boundary is allowed and after is excluded")
    func txtExactRanges() async {
        let fp = WI6Fixtures.fingerprint("c", format: .txt)
        let current = WI6Fixtures.chunk(
            fingerprint: fp, id: "txt:segment:0", index: 0,
            text: "0123456789", local: 0..<10, global: 0..<10
        )
        let before = WI6Fixtures.chunk(
            fingerprint: fp, id: "txt:segment:0", index: 0,
            text: "23", local: 2..<4, global: 2..<4
        )
        let after = WI6Fixtures.chunk(
            fingerprint: fp, id: "txt:segment:0", index: 0,
            text: "78", local: 7..<9, global: 7..<9
        )
        let boundary = WI6Fixtures.snapshot(
            fingerprint: fp, current: current,
            localBoundary: 5, globalBoundary: 5
        ).readSoFarBoundary
        let coordinator = neverCoordinator()
        #expect(await coordinator.authorizedText(
            before, boundary: boundary, toolName: "test", actionDescription: "read"
        )?.text == "23")
        #expect(await coordinator.authorizedText(
            after, boundary: boundary, toolName: "test", actionDescription: "read"
        ) == nil)
    }

    @Test("TXT range crossing UTF-16 boundary is clipped without unread suffix")
    func txtPartialOverlapClips() async {
        let fp = WI6Fixtures.fingerprint("d", format: .txt)
        let current = WI6Fixtures.chunk(
            fingerprint: fp, id: "txt:segment:0", index: 0,
            text: "0123456789", local: 0..<10, global: 0..<10
        )
        let crossing = WI6Fixtures.chunk(
            fingerprint: fp, id: "txt:segment:0", index: 0,
            text: "345678", local: 3..<9, global: 3..<9
        )
        let boundary = WI6Fixtures.snapshot(
            fingerprint: fp, current: current,
            localBoundary: 6, globalBoundary: 6
        ).readSoFarBoundary
        let safe = await neverCoordinator().authorizedText(
            crossing, boundary: boundary, toolName: "test", actionDescription: "read"
        )
        #expect(safe?.text == "345")
        #expect((safe?.text ?? "").contains("678") == false)
        #expect(safe?.globalEndUTF16 == 6)
    }

    @Test("Markdown clipping uses rendered structured UTF-16 coordinates")
    func markdownRenderedCoordinatesClip() async {
        let fp = WI6Fixtures.fingerprint("e", format: .md)
        let current = WI6Fixtures.chunk(
            fingerprint: fp, id: "md:segment:0", index: 0,
            text: "标题🙂结尾", local: 0..<6, global: 0..<6
        )
        let crossing = WI6Fixtures.chunk(
            fingerprint: fp, id: "md:segment:0", index: 0,
            text: "标题🙂结尾", local: 0..<6, global: 0..<6
        )
        let boundary = WI6Fixtures.snapshot(
            fingerprint: fp, current: current,
            localBoundary: 4, globalBoundary: 4
        ).readSoFarBoundary
        let safe = await neverCoordinator().authorizedText(
            crossing, boundary: boundary, toolName: "test", actionDescription: "read"
        )
        #expect(safe?.text == "标题🙂")
        #expect(safe?.text.utf16.count == 4)
    }

    @Test("Ask approval releases ahead candidate; denial releases nothing")
    func askApprovalAndDenial() async {
        let fp = WI6Fixtures.fingerprint("f", format: .pdf)
        let current = WI6Fixtures.chunk(
            fingerprint: fp, id: "pdf:page:0", index: 0,
            text: "current", page: 0, local: 0..<7
        )
        let future = WI6Fixtures.chunk(
            fingerprint: fp, id: "pdf:page:1", index: 1,
            text: "future", page: 1, local: 0..<6
        )
        let boundary = WI6Fixtures.snapshot(
            fingerprint: fp, current: current, localBoundary: 7
        ).readSoFarBoundary

        let denied = await askResult(
            future, boundary: boundary, response: .deny
        )
        #expect(denied == nil)
        let allowed = await askResult(
            future, boundary: boundary, response: .allowOnce
        )
        #expect(allowed?.text == "future")
    }

    @Test("Ask denial clips an exact overlap while approval releases it whole")
    func askPartialOverlap() async {
        let fingerprint = WI6Fixtures.fingerprint("0", format: .txt)
        let current = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "txt:segment:0", index: 0,
            text: "0123456789", local: 0..<10, global: 0..<10
        )
        let crossing = WI6Fixtures.chunk(
            fingerprint: fingerprint, id: "txt:segment:0", index: 0,
            text: "345678", local: 3..<9, global: 3..<9
        )
        let boundary = WI6Fixtures.snapshot(
            fingerprint: fingerprint, current: current,
            localBoundary: 6, globalBoundary: 6
        ).readSoFarBoundary

        let denied = await askResult(crossing, boundary: boundary, response: .deny)
        #expect(denied?.text == "345")
        let allowed = await askResult(
            crossing, boundary: boundary, response: .allowOnce
        )
        #expect(allowed?.text == "345678")
    }

    @Test("Whole-book mode releases otherwise-ahead content")
    func wholeBookAllowsFuture() async {
        let fp = WI6Fixtures.fingerprint("1", format: .pdf)
        let current = WI6Fixtures.chunk(
            fingerprint: fp, id: "pdf:page:0", index: 0,
            text: "current", page: 0, local: 0..<7
        )
        let future = WI6Fixtures.chunk(
            fingerprint: fp, id: "pdf:page:9", index: 9,
            text: "future", page: 9, local: 0..<6
        )
        let boundary = WI6Fixtures.snapshot(
            fingerprint: fp, current: current, localBoundary: 7
        ).readSoFarBoundary
        let coordinator = AICurrentBookRetrievalBoundary(
            authorizationGate: WI6Fixtures.gate(
                [.readAhead: .allow], readAhead: .wholeBookAllowed
            )
        )
        #expect(await coordinator.authorizedText(
            future, boundary: boundary, toolName: "test", actionDescription: "read"
        )?.text == "future")
    }

    @Test("atomic annotation candidate crossing boundary is wholly protected")
    func atomicOverlapDoesNotClipAnnotationText() async {
        let fp = WI6Fixtures.fingerprint("2", format: .txt)
        let current = WI6Fixtures.chunk(
            fingerprint: fp, id: "txt:segment:0", index: 0,
            text: "0123456789", local: 0..<10, global: 0..<10
        )
        let annotation = WI6Fixtures.chunk(
            fingerprint: fp, id: "txt:segment:0", index: 0,
            text: "note about future", local: 4..<8, global: 4..<8
        )
        let boundary = WI6Fixtures.snapshot(
            fingerprint: fp, current: current,
            localBoundary: 5, globalBoundary: 5
        ).readSoFarBoundary
        #expect(await neverCoordinator().authorizedText(
            annotation, boundary: boundary, toolName: "get_annotations",
            actionDescription: "read annotation", overlapPolicy: .atomic
        ) == nil)
    }

    private func neverCoordinator() -> AICurrentBookRetrievalBoundary {
        AICurrentBookRetrievalBoundary(
            authorizationGate: WI6Fixtures.gate(
                [.readAhead: .allow], readAhead: .neverReadAhead
            )
        )
    }

    private func askResult(
        _ chunk: AIDocumentChunk,
        boundary: AIReadSoFarBoundary,
        response: AIActionConfirmationResponse
    ) async -> AIDocumentChunk? {
        let store = WI6PreferencesStore(WI6Fixtures.preferences(
            [.readAhead: .allow], readAhead: .askBeforeReadingAhead
        ))
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        let resolver = resolveNextWI6Confirmation(on: broker, with: response)
        let coordinator = AICurrentBookRetrievalBoundary(
            authorizationGate: AIAgentToolExecutionGate(
                preferencesStore: store,
                broker: broker,
                confirmationAvailability: .brokerConnected
            )
        )
        let result = await coordinator.authorizedText(
            chunk, boundary: boundary, toolName: "test", actionDescription: "read"
        )
        await resolver.value
        return result
    }

}
