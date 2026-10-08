// Purpose: Focused test suite for Apple Foundation Models native Tool registration,
// contextual execution (AIToolExecutionContext), provenance propagation, multi-turn session reuse,
// and session isolation between readers.

import Testing
import Foundation
@testable import vreader

@Suite("AppleNativeToolCallingTests")
struct AppleNativeToolCallingTests {

    private final class ContextSpyTool: AIContextualTool, @unchecked Sendable {
        let name: String
        var receivedContexts: [AIToolExecutionContext] = []

        init(name: String = "context_spy") {
            self.name = name
        }

        var definition: ToolDefinition {
            ToolDefinition(
                name: name,
                description: "Spy tool recording execution context",
                inputSchema: .object(["type": .string("object")])
            )
        }

        func run(_ input: JSONValue) async -> ToolResult {
            await run(input, context: AIToolExecutionContext())
        }

        func run(_ input: JSONValue, context: AIToolExecutionContext) async -> ToolResult {
            receivedContexts.append(context)
            return ToolResult(toolUseID: context.toolCallID, content: "Spy success", isError: false)
        }
    }

    private final class ProvenanceEmittingTool: AIContextualTool, @unchecked Sendable {
        let name: String
        let shouldFail: Bool
        let sourceLocator: Locator

        init(name: String, shouldFail: Bool, locator: Locator) {
            self.name = name
            self.shouldFail = shouldFail
            self.sourceLocator = locator
        }

        var definition: ToolDefinition {
            ToolDefinition(
                name: name,
                description: "Emits provenance source",
                inputSchema: .object(["type": .string("object")])
            )
        }

        func run(_ input: JSONValue) async -> ToolResult {
            await run(input, context: AIToolExecutionContext())
        }

        func run(_ input: JSONValue, context: AIToolExecutionContext) async -> ToolResult {
            let prov = AISourceProvenance(
                bookFingerprintKey: "book-1",
                bookTitle: "Test Book",
                locator: sourceLocator,
                snippet: "Provenance snippet from \(name)",
                retrievalMethod: .semanticSearch,
                score: 0.95,
                aheadOfReader: false,
                toolCallID: context.toolCallID
            )
            await context.eventSink.emit(AIToolEvent(
                toolCallID: context.toolCallID,
                toolName: name,
                phase: .running,
                sources: [prov]
            ))

            if shouldFail {
                return ToolResult(toolUseID: context.toolCallID, content: "Tool exploded", isError: true)
            } else {
                return ToolResult(toolUseID: context.toolCallID, content: "Tool succeeded", isError: false)
            }
        }
    }

    private final class TestMockSession: AppleLanguageModelSessionProtocol, @unchecked Sendable {
        let instructions: String
        let tools: [Any]
        var respondCount = 0
        var onRespond: (@Sendable (String) async throws -> String)?

        init(instructions: String, tools: [Any]) {
            self.instructions = instructions
            self.tools = tools
        }

        func respond(to prompt: String) async throws -> String {
            respondCount += 1
            if let onRespond {
                return try await onRespond(prompt)
            }
            return "Session response to: \(prompt)"
        }
    }

    // MARK: - 1. Native Tool Registration & Contextual Dispatch

    @Test func backendRegistersNativeToolsAndPassesAIToolExecutionContext() async throws {
        let spy = ContextSpyTool(name: "search_chapter")
        let registry = AIToolRegistry([spy])
        let adapter = AppleFoundationModelsToolAdapter(registry: registry, executionGate: .productionUnavailable())

        let expectedTurnID = "turn-abc-123"
        let expectedReaderToken = UUID()
        let expectedDocSessionID = AIDocumentSessionID(fingerprintKey: "book-test", readerToken: expectedReaderToken)

        var createdSession: TestMockSession?
        let backend = AppleFoundationModelsBackend(
            availability: AppleFoundationModelsAvailability(state: .available),
            sessionFactory: { instructions, tools in
                let sess = TestMockSession(instructions: instructions, tools: tools)
                sess.onRespond = { prompt in
                    // Simulate native model calling the registered tool via adapter
                    let res = await adapter.invokeNative(
                        toolName: "search_chapter",
                        rawArguments: "{\"query\": \"intro\"}",
                        callID: "call-native-999",
                        turnID: expectedTurnID,
                        documentSessionID: expectedDocSessionID
                    )
                    return "Result: \(res.content)"
                }
                createdSession = sess
                return sess
            }
        )

        let result = try await backend.executeTurn(
            systemPrompt: "You are a reading assistant",
            prompt: "Find chapter intro",
            toolAdapter: adapter,
            documentSessionID: expectedDocSessionID,
            turnID: expectedTurnID
        )

        #expect(createdSession != nil)
        #expect(result.finalText.contains("Spy success"))
        #expect(spy.receivedContexts.count == 1)

        let ctx = try #require(spy.receivedContexts.first)
        #expect(ctx.turnID == expectedTurnID)
        #expect(ctx.toolCallID == "call-native-999")
        #expect(ctx.readerSessionID == expectedDocSessionID)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let bridge = AppleNativeToolBridge(
                name: "search_chapter",
                description: "Test description",
                adapter: adapter,
                turnID: expectedTurnID,
                documentSessionID: expectedDocSessionID,
                sink: ProvenanceTapSink()
            )
            let callOutput = try await bridge.call(arguments: .init(input: "{\"query\": \"intro\"}"))
            #expect(callOutput.contains("Spy success"))
        }
        #endif
    }

    // MARK: - 2. Provenance Capture & Failed Tool Source Exclusion

    @Test func successfulToolEmitsProvenanceAndFailedToolSourceIsDiscarded() async throws {
        let fp = DocumentFingerprint(scheme: "test", value: "book-1")
        let locSuccess = Locator(bookFingerprint: fp, href: "ch1.xhtml")
        let locFailed = Locator(bookFingerprint: fp, href: "ch2.xhtml")

        let successTool = ProvenanceEmittingTool(name: "fetch_success", shouldFail: false, locator: locSuccess)
        let failTool = ProvenanceEmittingTool(name: "fetch_failure", shouldFail: true, locator: locFailed)

        let registry = AIToolRegistry([successTool, failTool])
        let adapter = AppleFoundationModelsToolAdapter(registry: registry, executionGate: .productionUnavailable())

        let tapSink = ProvenanceTapSink()
        let turnID = "turn-prov-1"

        // 1. Run success tool
        let resSuccess = await adapter.invokeNative(
            toolName: "fetch_success",
            rawArguments: "{}",
            callID: "call-ok",
            turnID: turnID,
            sink: tapSink
        )
        #expect(!resSuccess.isError)

        // 2. Run failing tool
        let resFail = await adapter.invokeNative(
            toolName: "fetch_failure",
            rawArguments: "{}",
            callID: "call-fail",
            turnID: turnID,
            sink: tapSink
        )
        #expect(resFail.isError)

        // Verify committed vs discarded sources
        let collected = await tapSink.collectedSources()
        #expect(collected.count == 1)
        #expect(collected.first?.locator.href == "ch1.xhtml")
        #expect(collected.first?.snippet.contains("fetch_success") == true)

        let citations = collected.compactMap { $0.toChatCitation() }
        #expect(citations.count == 1)
        #expect(citations.first?.href == "ch1.xhtml")
    }

    // MARK: - 3. Multi-Turn Session Reuse & Reader Token Isolation

    @Test func sameReaderSessionReusesInstanceWhileDifferentTokenGetsNewSession() async throws {
        var instantiatedSessions: [TestMockSession] = []

        let backend = AppleFoundationModelsBackend(
            availability: AppleFoundationModelsAvailability(state: .available),
            sessionFactory: { instructions, tools in
                let s = TestMockSession(instructions: instructions, tools: tools)
                instantiatedSessions.append(s)
                return s
            }
        )

        let tokenA = UUID()
        let tokenB = UUID()
        let sessionID_A = AIDocumentSessionID(fingerprintKey: "book-shared", readerToken: tokenA)
        let sessionID_B = AIDocumentSessionID(fingerprintKey: "book-shared", readerToken: tokenB) // same book, different token

        // Turn 1 for Reader A
        _ = try await backend.executeTurn(
            systemPrompt: "System",
            prompt: "Turn 1 for A",
            documentSessionID: sessionID_A,
            turnID: "turn-1"
        )
        #expect(instantiatedSessions.count == 1)
        let sessionA = instantiatedSessions[0]
        #expect(sessionA.respondCount == 1)

        // Turn 2 for Reader A (must reuse sessionA)
        _ = try await backend.executeTurn(
            systemPrompt: "System",
            prompt: "Turn 2 for A",
            documentSessionID: sessionID_A,
            turnID: "turn-2"
        )
        #expect(instantiatedSessions.count == 1)
        #expect(sessionA.respondCount == 2)

        // Turn 1 for Reader B on the SAME book (must create distinct session instance)
        _ = try await backend.executeTurn(
            systemPrompt: "System",
            prompt: "Turn 1 for B",
            documentSessionID: sessionID_B,
            turnID: "turn-3"
        )
        #expect(instantiatedSessions.count == 2)
        let sessionB = instantiatedSessions[1]
        #expect(sessionA !== sessionB)
        #expect(sessionB.respondCount == 1)
        #expect(sessionA.respondCount == 2)
    }

    // MARK: - 4. Cancellation Safety

    @Test func cancelledTaskThrowsCancellationErrorPromptly() async {
        let backend = AppleFoundationModelsBackend(
            availability: AppleFoundationModelsAvailability(state: .available),
            sessionFactory: { instructions, tools in
                let s = TestMockSession(instructions: instructions, tools: tools)
                s.onRespond = { _ in
                    try await Task.sleep(nanoseconds: 500_000_000)
                    return "Late output"
                }
                return s
            }
        )

        let task = Task {
            try await backend.executeTurn(
                systemPrompt: "Sys",
                prompt: "Slow prompt",
                documentSessionID: nil,
                turnID: "turn-cancel"
            )
        }

        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Success: cleanly cancelled
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
