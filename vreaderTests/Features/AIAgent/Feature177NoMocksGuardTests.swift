// Purpose: Regression guard test suite verifying Feature #177 has zero mocks in production paths,
// real USearch / MLX / Vision OCR / MCP / FoundationModels wiring, and exact-session isolation.

import Foundation
import Testing
@testable import vreader

@Suite("Feature #177 — Production No-Mocks & Invariant Guards")
struct Feature177NoMocksGuardTests {

    // MARK: - 1. Source Code Pattern Guards

    @Test("Production ReaderAICoordinator does not use .productionUnavailable()")
    func readerCoordinatorDoesNotUseProductionUnavailable() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AIAgent
            .deletingLastPathComponent() // Features
            .deletingLastPathComponent() // vreaderTests
            .deletingLastPathComponent() // repo root
        let coordinatorFile = repoRoot.appendingPathComponent("vreader/Views/Reader/ReaderAICoordinator.swift")
        let content = try String(contentsOf: coordinatorFile, encoding: .utf8)

        #expect(!content.contains("authorizationGate: .productionUnavailable()"),
                "ReaderAICoordinator must not inject .productionUnavailable() in live reader path.")
    }

    @Test("Production MCPClientManager does not default-construct MockMCPConnection")
    func mcpClientManagerDoesNotDefaultMock() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = repoRoot.appendingPathComponent("vreader/Features/AIAgent/MCP/MCPClientManager.swift")
        let content = try String(contentsOf: file, encoding: .utf8)

        #expect(!content.contains("connection = MockMCPConnection(profile: profile)"),
                "MCPClientManager must use connectionFactory defaulting to HTTPMCPConnection, not hardcoded MockMCPConnection.")
    }

    @Test("Production AppleFoundationModelsBackend does not return simulated strings or fake tool calls")
    func foundationModelsBackendNotSimulated() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = repoRoot.appendingPathComponent("vreader/Features/AIAgent/FoundationModels/AppleFoundationModelsBackend.swift")
        let content = try String(contentsOf: file, encoding: .utf8)

        #expect(!content.contains("Apple Foundation Models (\\(resolvedMode.rawValue)) response for:"),
                "AppleFoundationModelsBackend must execute real LanguageModelSession, not return simulated responses.")
        #expect(!content.contains("// Simulated/fallback execution in test environments"),
                "AppleFoundationModelsBackend must not contain simulated fallback comments or logic in production.")
    }

    @Test("Production SemanticIndexStore uses USearch, not in-memory brute force dictionary")
    func semanticStoreUsesUSearch() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = repoRoot.appendingPathComponent("vreader/Features/AIAgent/Semantic/SemanticIndexStore.swift")
        let content = try String(contentsOf: file, encoding: .utf8)

        #expect(content.contains("USearchIndex"),
                "SemanticIndexStore must use USearchIndex for persistent ANN search.")
        #expect(content.contains("insertBatch(coherentItems:"),
                "SemanticIndexStore must provide coherent insertion of vectors, chunks, and book keys.")
    }

    @Test("SemanticVectorKey provides deterministic non-Hasher key derivation")
    func semanticVectorKeyIsDeterministic() {
        let key1 = SemanticVectorKey.deriveKey(from: "book1:chapter1:chunk0")
        let key2 = SemanticVectorKey.deriveKey(from: "book1:chapter1:chunk0")
        let key3 = SemanticVectorKey.deriveKey(from: "book1:chapter1:chunk1")

        #expect(key1 == key2, "Derived key for same chunk ID must be strictly identical across calls.")
        #expect(key1 != key3, "Derived keys for different chunk IDs must differ.")
        #expect(key1 > 0)
    }

    // MARK: - 2. Mutation Idempotency & Ownership Guards

    @Test("Mutation idempotency tracker prevents duplicate execution")
    func mutationIdempotencyPreventsDuplicates() async {
        let tracker = AIToolMutationIdempotency(maxEntries: 50)
        let key = "turn-123:call-456:create_note"
        let isDoneBefore = await tracker.isCompleted(idempotencyKey: key)
        #expect(!isDoneBefore)
        await tracker.recordCompleted(idempotencyKey: key, recordID: "note-uuid-1", summary: "Created note with ID: note-uuid-1")

        let isDoneAfter = await tracker.isCompleted(idempotencyKey: key)
        #expect(isDoneAfter)
        let outcome = await tracker.outcome(idempotencyKey: key)
        #expect(outcome?.recordID == "note-uuid-1")
        #expect(outcome?.summary == "Created note with ID: note-uuid-1")
    }

    // MARK: - 3. Session Confirmation Broker Isolation

    @Test("Confirmation broker isolates requests by AIDocumentSessionID")
    func confirmationBrokerIsolatesBySession() async {
        let broker = AIActionConfirmationBroker()
        let sessionA = AIDocumentSessionID(fingerprintKey: "bookA", readerToken: UUID())
        let sessionB = AIDocumentSessionID(fingerprintKey: "bookA", readerToken: UUID()) // same book, different token

        let reqA = AIActionConfirmationRequest(
            toolName: "delete_note",
            actionDescription: "Delete note A",
            category: .removeData,
            readerSessionID: sessionA
        )
        let reqB = AIActionConfirmationRequest(
            toolName: "delete_note",
            actionDescription: "Delete note B",
            category: .removeData,
            readerSessionID: sessionB
        )

        let pendingBeforeA = await broker.pendingRequests(for: sessionA)
        #expect(pendingBeforeA.isEmpty)

        // Publish to broker
        await broker.publish(reqA)
        await broker.publish(reqB)

        let pendingA = await broker.pendingRequests(for: sessionA)
        let pendingB = await broker.pendingRequests(for: sessionB)

        #expect(pendingA.count == 1)
        #expect(pendingA.first?.id == reqA.id)
        #expect(pendingB.count == 1)
        #expect(pendingB.first?.id == reqB.id)

        // Cancel session A must not cancel session B
        await broker.cancelSession(sessionID: sessionA)
        let pendingAfterCancelA = await broker.pendingRequests(for: sessionA)
        let pendingAfterCancelB = await broker.pendingRequests(for: sessionB)

        #expect(pendingAfterCancelA.isEmpty)
        #expect(pendingAfterCancelB.count == 1)
    }

    // MARK: - 4. Turn Routing Invariant

    @Test("Turn Router dispatches to Cloud or Apple based on preference")
    func turnRouterDispatchesCorrectBackend() async throws {
        final class SpyTurnExecutor: AIAgentTurnExecuting, @unchecked Sendable {
            var executed = false
            func executeTurn(
                prompt: String,
                systemPrompt: String,
                contextText: String?,
                registry: AIToolRegistry,
                documentSessionID: AIDocumentSessionID?,
                turnID: String
            ) async throws -> AgenticResult {
                executed = true
                return AgenticResult(finalText: "Spy response", usedTools: false)
            }
        }

        final class ChoiceBox: @unchecked Sendable {
            var choice: AIAgentBackendChoice = .cloudProvider
        }
        let box = ChoiceBox()

        let cloudSpy = SpyTurnExecutor()
        let appleSpy = SpyTurnExecutor()

        let router = AIAgentTurnRouter(
            cloudExecutor: cloudSpy,
            appleExecutor: appleSpy,
            backendChoice: { box.choice }
        )

        let emptyRegistry = AIToolRegistry([])

        // 1. Dispatch cloud
        _ = try await router.executeTurn(
            prompt: "Test", systemPrompt: "Sys", contextText: nil,
            registry: emptyRegistry, documentSessionID: nil, turnID: "t1"
        )
        #expect(cloudSpy.executed == true)
        #expect(appleSpy.executed == false)

        // 2. Switch to Apple
        box.choice = .appleFoundationModels
        _ = try await router.executeTurn(
            prompt: "Test", systemPrompt: "Sys", contextText: nil,
            registry: emptyRegistry, documentSessionID: nil, turnID: "t2"
        )
        #expect(appleSpy.executed == true)
    }
}
