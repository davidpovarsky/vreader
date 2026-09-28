import Foundation
import Testing
@testable import vreader

@Suite("Feature #177 WI-5 — action confirmation broker")
struct AIActionConfirmationBrokerTests {
    private static func makeBroker() -> (AIActionConfirmationBroker, AIAgentPreferencesStore) {
        let store = AIAgentPreferencesStore(
            preferences: MockPreferenceStore(),
            storageKey: "tests.confirmation-preferences"
        )
        return (AIActionConfirmationBroker(preferencesStore: store), store)
    }

    private static func request(
        id: UUID = UUID(),
        category: AIToolPermissionCategory = .navigateReader,
        destructive: Bool = false,
        rememberEligible: Bool = true,
        turnID: String? = "turn-1"
    ) -> AIActionConfirmationRequest {
        AIActionConfirmationRequest(
            id: id,
            toolName: "test_tool",
            actionDescription: "Perform a test action",
            permissionCategory: category,
            isDestructive: destructive,
            rememberAllowEligible: rememberEligible,
            turnID: turnID
        )
    }

    private static func startPending(
        _ request: AIActionConfirmationRequest,
        broker: AIActionConfirmationBroker
    ) async -> (
        Task<AIActionConfirmationOutcome, Never>,
        AsyncStream<[AIActionConfirmationRequest]>.Iterator
    ) {
        let stream = await broker.pendingRequestUpdates()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next() // deterministic initial snapshot
        let task = Task { await broker.requestConfirmation(request) }
        let pending = await iterator.next()
        #expect(pending?.map(\.id) == [request.id])
        return (task, iterator)
    }

    @Test("allow once resumes exactly once")
    func allowOnce() async {
        let (broker, _) = Self.makeBroker()
        let request = Self.request()
        let (task, _) = await Self.startPending(request, broker: broker)

        #expect(await broker.resolve(request.id, with: .allowOnce))
        #expect(await task.value == .allowed)
        #expect(!(await broker.resolve(request.id, with: .allowOnce)))
    }

    @Test("deny resumes exactly once")
    func deny() async {
        let (broker, _) = Self.makeBroker()
        let request = Self.request()
        let (task, _) = await Self.startPending(request, broker: broker)

        #expect(await broker.resolve(request.id, with: .deny))
        #expect(await task.value == .denied)
        #expect(!(await broker.resolve(request.id, with: .deny)))
    }

    @Test("remember allow persists for a safe category")
    func rememberSafeAllow() async {
        let (broker, store) = Self.makeBroker()
        let request = Self.request(category: .navigateReader)
        let (task, _) = await Self.startPending(request, broker: broker)

        #expect(await broker.resolve(request.id, with: .alwaysAllow))
        #expect(await task.value == .allowed)
        #expect(await store.load().decision(for: .navigateReader) == .allow)
    }

    @Test("destructive remember allow is rejected and not persisted")
    func destructiveRememberRejected() async {
        let (broker, store) = Self.makeBroker()
        let request = Self.request(
            category: .removeData,
            destructive: true,
            rememberEligible: true
        )
        let (task, _) = await Self.startPending(request, broker: broker)

        #expect(!(await broker.resolve(request.id, with: .alwaysAllow)))
        #expect(await broker.resolve(request.id, with: .allowOnce))
        #expect(await task.value == .allowed)
        #expect(await store.load().decision(for: .removeData) != .allow)
    }

    @Test("decoded remove-data requests cannot forge remember eligibility")
    func decodedDestructiveRequestIsNormalized() async throws {
        let id = UUID()
        let data = Data(
            #"{"id":"\#(id.uuidString)","toolName":"delete_note","actionDescription":"Delete a note","permissionCategory":"removeData","metadata":{},"isDestructive":false,"rememberAllowEligible":true}"#.utf8
        )
        let request = try JSONDecoder().decode(AIActionConfirmationRequest.self, from: data)
        #expect(request.isDestructive)
        #expect(!request.rememberAllowEligible)

        let (broker, store) = Self.makeBroker()
        let (task, _) = await Self.startPending(request, broker: broker)
        #expect(!(await broker.resolve(request.id, with: .alwaysAllow)))
        #expect(await broker.resolve(request.id, with: .deny))
        #expect(await task.value == .denied)
        #expect(await store.load().decision(for: .removeData) != .allow)
    }

    @Test("task cancellation terminates pending confirmation")
    func cancellationWhilePending() async {
        let (broker, _) = Self.makeBroker()
        let request = Self.request()
        let pending = await Self.startPending(request, broker: broker)
        let task = pending.0
        var updates = pending.1

        task.cancel()
        #expect(!(await broker.resolve(request.id, with: .alwaysAllow)))
        #expect(await task.value == .cancelled)
        #expect(await updates.next()?.isEmpty == true)
        #expect(await broker.pendingRequestCount == 0)
    }

    @Test("teardown cancels every pending confirmation")
    func teardownCancelsPending() async {
        let (broker, _) = Self.makeBroker()
        let request = Self.request()
        let (task, _) = await Self.startPending(request, broker: broker)

        await broker.cancelAll()
        #expect(await task.value == .cancelled)
        #expect(await broker.pendingRequestCount == 0)
    }

    @Test("superseded turn cannot later resume old work")
    func supersededTurnCannotResume() async {
        let (broker, _) = Self.makeBroker()
        let request = Self.request(turnID: "old-turn")
        let (task, _) = await Self.startPending(request, broker: broker)

        await broker.cancelTurn("old-turn")
        #expect(await task.value == .cancelled)
        #expect(!(await broker.resolve(request.id, with: .allowOnce)))
    }

    @Test("duplicate resolution cannot double-resume")
    func duplicateResolve() async {
        let (broker, _) = Self.makeBroker()
        let request = Self.request()
        let (task, _) = await Self.startPending(request, broker: broker)

        #expect(await broker.resolve(request.id, with: .deny))
        #expect(!(await broker.resolve(request.id, with: .allowOnce)))
        #expect(await task.value == .denied)
    }

    @Test("a response for another request changes nothing")
    func wrongRequestID() async {
        let (broker, _) = Self.makeBroker()
        let request = Self.request()
        let (task, _) = await Self.startPending(request, broker: broker)

        #expect(!(await broker.resolve(UUID(), with: .allowOnce)))
        #expect(await broker.pendingRequestCount == 1)
        #expect(await broker.resolve(request.id, with: .deny))
        #expect(await task.value == .denied)
    }

    @Test("resolution and invalidation leave no continuation pending")
    func noPendingContinuationRemains() async {
        let (broker, _) = Self.makeBroker()
        let first = Self.request()
        let (firstTask, _) = await Self.startPending(first, broker: broker)
        #expect(await broker.resolve(first.id, with: .allowOnce))
        #expect(await firstTask.value == .allowed)

        let second = Self.request()
        let (secondTask, _) = await Self.startPending(second, broker: broker)
        await broker.invalidate(second.id)
        #expect(await secondTask.value == .cancelled)
        #expect(await broker.pendingRequestCount == 0)
    }
}
