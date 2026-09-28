import Foundation
import Testing
@testable import vreader

@Suite("Feature #177 WI-5 — read-ahead authorization bridge")
struct AIReadAheadAuthorizationTests {
    private let fingerprint = DocumentFingerprint.validated(
        contentSHA256: String(repeating: "d", count: 64),
        fileByteCount: 4_096,
        format: .pdf
    )!

    private func locator(page: Int) -> Locator {
        Locator.validated(bookFingerprint: fingerprint, page: page)!
    }

    private var boundary: AIReadSoFarBoundary {
        AIReadSoFarBoundary(
            locator: locator(page: 4),
            sourceUnitID: "pdf-page-4",
            sourceUnitIndex: 4,
            localOffsetUTF16: 50
        )
    }

    private func chunk(page: Int, localStart: Int = 0) -> AIDocumentChunk {
        AIDocumentChunk(
            id: "pdf:\(page):\(localStart)",
            bookFingerprintKey: fingerprint.canonicalKey,
            sourceUnitID: "pdf-page-\(page)",
            sourceUnitIndex: page,
            text: "protected text",
            locator: locator(page: page),
            sourceLabel: "Page \(page + 1)",
            chapterTitle: nil,
            pageIndex: page,
            href: nil,
            localStartUTF16: localStart,
            localEndUTF16: localStart + 14,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )
    }

    private func makeBridge(
        mode: AIReadAheadMode,
        readAheadDecision: AIToolPermissionDecision = .allow
    ) async -> (AIReadAheadAuthorizationBridge, AIActionConfirmationBroker) {
        let store = AIAgentPreferencesStore(
            preferences: MockPreferenceStore(),
            storageKey: "tests.read-ahead-preferences"
        )
        await store.setReadAheadMode(mode)
        await store.setDecision(readAheadDecision, for: .readAhead)
        let broker = AIActionConfirmationBroker(preferencesStore: store)
        return (
            AIReadAheadAuthorizationBridge(preferencesStore: store, broker: broker),
            broker
        )
    }

    private func context() -> AIToolAuthorizationContext {
        AIToolAuthorizationContext(
            toolName: "read_ahead_test",
            actionDescription: "Read a later page",
            permissionCategory: .readAhead,
            bookFingerprintKey: fingerprint.canonicalKey,
            sourceLocator: locator(page: 4)
        )
    }

    @Test("never mode blocks a proven-ahead candidate")
    func neverBlocksAhead() async {
        let (bridge, _) = await makeBridge(mode: .neverReadAhead)
        #expect(await bridge.authorizedCandidate(
            chunk(page: 5), boundary: boundary, context: context()
        ) == nil)
    }

    @Test("ask mode requires confirmation without exposing content")
    func askRequiresConfirmation() async {
        let (bridge, broker) = await makeBridge(mode: .askBeforeReadingAhead)
        let stream = await broker.pendingRequestUpdates()
        var updates = stream.makeAsyncIterator()
        _ = await updates.next()

        let task = Task {
            await bridge.authorizedCandidate(
                chunk(page: 5), boundary: boundary, context: context()
            )
        }
        let pending = await updates.next()
        #expect(pending?.count == 1)
        #expect(pending?.first?.permissionCategory == .readAhead)
        #expect(pending?.first?.sourceLocator == locator(page: 5))

        task.cancel()
        #expect(await task.value == nil)
    }

    @Test("whole-book mode permits an ahead candidate")
    func wholeBookAllowsAhead() async {
        let candidate = chunk(page: 5)
        let (bridge, _) = await makeBridge(mode: .wholeBookAllowed)
        #expect(await bridge.authorizedCandidate(
            candidate, boundary: boundary, context: context()
        ) == candidate)
    }

    @Test("current and prior content remain allowed")
    func currentAndBehindAllowed() async {
        let (bridge, _) = await makeBridge(
            mode: .neverReadAhead,
            readAheadDecision: .deny
        )
        #expect(await bridge.authorizedCandidate(
            chunk(page: 3), boundary: boundary, context: context()
        ) != nil)
        #expect(await bridge.authorizedCandidate(
            chunk(page: 4, localStart: 50), boundary: boundary, context: context()
        ) != nil)
    }

    @Test("unknown ordering fails closed")
    func unknownOrderingFailsClosed() async {
        let unknown = AIDocumentChunk(
            id: "unknown",
            bookFingerprintKey: fingerprint.canonicalKey,
            sourceUnitID: "unknown-source",
            sourceUnitIndex: nil,
            text: "unknown text",
            locator: Locator.validated(bookFingerprint: fingerprint)!,
            sourceLabel: nil,
            chapterTitle: nil,
            pageIndex: nil,
            href: nil,
            localStartUTF16: nil,
            localEndUTF16: nil,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )
        let (bridge, _) = await makeBridge(mode: .neverReadAhead)

        #expect(await bridge.authorizedCandidate(
            unknown, boundary: boundary, context: context()
        ) == nil)
    }

    @Test("denying an ask request never releases ahead content")
    func deniedAskDoesNotLeak() async {
        let (bridge, broker) = await makeBridge(mode: .askBeforeReadingAhead)
        let stream = await broker.pendingRequestUpdates()
        var updates = stream.makeAsyncIterator()
        _ = await updates.next()
        let task = Task {
            await bridge.authorizedCandidate(
                chunk(page: 5), boundary: boundary, context: context()
            )
        }
        let request = await updates.next()?.first
        #expect(request != nil)

        #expect(await broker.resolve(request!.id, with: .deny))
        #expect(await task.value == nil)
    }

    @Test("cancelling pending read-ahead approval cleans up")
    func cancellationCleansUp() async {
        let (bridge, broker) = await makeBridge(mode: .askBeforeReadingAhead)
        let stream = await broker.pendingRequestUpdates()
        var updates = stream.makeAsyncIterator()
        _ = await updates.next()
        let task = Task {
            await bridge.authorizedCandidate(
                chunk(page: 5), boundary: boundary, context: context()
            )
        }
        _ = await updates.next()

        task.cancel()
        #expect(await task.value == nil)
        #expect(await updates.next()?.isEmpty == true)
        #expect(await broker.pendingRequestCount == 0)
    }
}
