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

    private final class SessionBox: @unchecked Sendable {
        var session: TestMockSession?
        var sessions: [TestMockSession] = []
    }

    // MARK: - 1. Native Tool Registration, Multi-Turn Binding & Contextual Dispatch

    @Test func backendRegistersNativeToolsAndRefreshesPerTurnContextAcrossMultiTurnSessionReuse() async throws {
        let fp = DocumentFingerprint(
            contentSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            fileByteCount: 4096,
            format: .epub
        )
        let locTurn1 = try #require(Locator.validated(bookFingerprint: fp, href: "ch1.xhtml"))
        let locTurn2 = try #require(Locator.validated(bookFingerprint: fp, href: "ch2.xhtml"))

        final class DynamicTurnTool: AIContextualTool, @unchecked Sendable {
            let name: String
            let locator: Locator
            let snippetText: String
            var receivedContexts: [AIToolExecutionContext] = []

            init(name: String, locator: Locator, snippetText: String) {
                self.name = name
                self.locator = locator
                self.snippetText = snippetText
            }

            var definition: ToolDefinition {
                ToolDefinition(
                    name: name,
                    description: "Emits provenance and records execution context",
                    inputSchema: .object(["type": .string("object")])
                )
            }

            func run(_ input: JSONValue) async -> ToolResult {
                await run(input, context: AIToolExecutionContext())
            }

            func run(_ input: JSONValue, context: AIToolExecutionContext) async -> ToolResult {
                receivedContexts.append(context)
                let prov = AISourceProvenance(
                    bookFingerprintKey: locator.bookFingerprint.canonicalKey,
                    bookTitle: "Book One",
                    locator: locator,
                    sourceLabel: locator.href,
                    chapterTitle: locator.href,
                    href: locator.href,
                    snippet: snippetText,
                    retrievalMethod: .semanticSearch,
                    score: 0.98,
                    aheadOfReader: false,
                    toolCallID: context.toolCallID
                )
                await context.eventSink.emit(AIToolEvent(
                    toolCallID: context.toolCallID,
                    toolName: name,
                    phase: .running,
                    sources: [prov]
                ))
                return ToolResult(toolUseID: context.toolCallID, content: "Found: \(snippetText)", isError: false)
            }
        }

        let toolTurn1 = DynamicTurnTool(name: "search_chapter", locator: locTurn1, snippetText: "Source A from Turn 1")
        let toolTurn2 = DynamicTurnTool(name: "search_chapter", locator: locTurn2, snippetText: "Source B from Turn 2")

        let adapterTurn1 = AppleFoundationModelsToolAdapter(
            registry: AIToolRegistry([toolTurn1]),
            executionGate: .productionUnavailable()
        )
        let adapterTurn2 = AppleFoundationModelsToolAdapter(
            registry: AIToolRegistry([toolTurn2]),
            executionGate: .productionUnavailable()
        )

        let readerToken = UUID()
        let docSessionID = AIDocumentSessionID(fingerprintKey: fp.canonicalKey, readerToken: readerToken)
        let box = SessionBox()

        let backend = AppleFoundationModelsBackend(
            availability: AppleFoundationModelsAvailability(state: .available),
            sessionFactory: { instructions, tools in
                let sess = TestMockSession(instructions: instructions, tools: tools)
                sess.onRespond = { [weak sess] prompt in
                    // Crucial: invoke the registered native AppleNativeToolBridge from `sess?.tools`
                    // (created on Turn 1) to prove Turn 2 does NOT stay bound to Turn 1's turnID/sink/adapter.
                    #if canImport(FoundationModels)
                    if #available(iOS 26.0, macOS 26.0, *),
                       let bridge = sess?.tools.first as? AppleNativeToolBridge {
                        let out = try await bridge.call(arguments: .init(input: "{\"query\": \"\(prompt)\"}"))
                        return "Model answer using \(out)"
                    }
                    #endif
                    return "Fallback answer"
                }
                box.sessions.append(sess)
                box.session = sess
                return sess
            }
        )

        // Turn 1
        let result1 = try await backend.executeTurn(
            systemPrompt: "You are a reading assistant",
            prompt: "Question 1",
            toolAdapter: adapterTurn1,
            documentSessionID: docSessionID,
            turnID: "turn-1",
            conversationID: "conv-alpha"
        )

        #expect(box.sessions.count == 1)
        let reusedSession = try #require(box.session)
        #expect(reusedSession.respondCount == 1)
        #expect(result1.usedTools == true)
        #expect(toolTurn1.receivedContexts.count == 1)
        #expect(toolTurn1.receivedContexts.first?.turnID == "turn-1")
        #expect(toolTurn1.receivedContexts.first?.readerSessionID == docSessionID)
        #expect(result1.sourceProvenances.count == 1)
        #expect(result1.sourceProvenances.first?.locator?.href == "ch1.xhtml")
        #expect(result1.citations.count == 1)
        #expect(result1.citations.first?.locator?.href == "ch1.xhtml")

        // Turn 2 on the SAME session: must reuse `reusedSession`, invoke `toolTurn2` with `turn-2`,
        // and collect Turn 2's provenance & citations into Turn 2's sink (not Turn 1's).
        let result2 = try await backend.executeTurn(
            systemPrompt: "You are a reading assistant",
            prompt: "Question 2",
            toolAdapter: adapterTurn2,
            documentSessionID: docSessionID,
            turnID: "turn-2",
            conversationID: "conv-alpha"
        )

        #expect(box.sessions.count == 1)
        #expect(reusedSession.respondCount == 2)
        #expect(result2.usedTools == true)
        #expect(toolTurn2.receivedContexts.count == 1)
        let ctx2 = try #require(toolTurn2.receivedContexts.first)
        #expect(ctx2.turnID == "turn-2")
        #expect(ctx2.readerSessionID == docSessionID)
        #expect(ctx2.toolCallID != toolTurn1.receivedContexts.first?.toolCallID)

        #expect(result2.sourceProvenances.count == 1)
        #expect(result2.sourceProvenances.first?.locator?.href == "ch2.xhtml")
        #expect(result2.sourceProvenances.first?.snippet == "Source B from Turn 2")
        #expect(result2.citations.count == 1)
        #expect(result2.citations.first?.locator?.href == "ch2.xhtml")
    }

    // MARK: - 2. Tool Without Source Provenance Sets usedTools == true

    @Test func nativeToolWithoutSourceProvenanceStillMarksUsedToolsTrue() async throws {
        let spy = ContextSpyTool(name: "list_library")
        let registry = AIToolRegistry([spy])
        let adapter = AppleFoundationModelsToolAdapter(
            registry: registry,
            executionGate: .productionUnavailable()
        )

        let backend = AppleFoundationModelsBackend(
            availability: AppleFoundationModelsAvailability(state: .available),
            sessionFactory: { instructions, tools in
                let sess = TestMockSession(instructions: instructions, tools: tools)
                sess.onRespond = { [weak sess] _ in
                    #if canImport(FoundationModels)
                    if #available(iOS 26.0, macOS 26.0, *),
                       let bridge = sess?.tools.first as? AppleNativeToolBridge {
                        let out = try await bridge.call(arguments: .init(input: "{}"))
                        return "Listed: \(out)"
                    }
                    #endif
                    return "No bridge"
                }
                return sess
            }
        )

        let result = try await backend.executeTurn(
            systemPrompt: "Assistant",
            prompt: "List my library",
            toolAdapter: adapter,
            documentSessionID: AIDocumentSessionID(fingerprintKey: "epub:4096:aaaa", readerToken: UUID()),
            turnID: "turn-no-source",
            conversationID: "conv-list"
        )

        #expect(spy.receivedContexts.count == 1)
        #expect(result.usedTools == true)
        #expect(result.citations.isEmpty)
        #expect(result.sourceProvenances.isEmpty)
    }

    // MARK: - 3. Provenance Capture & Failed Tool Source Exclusion

    @Test func successfulToolEmitsProvenanceAndFailedToolSourceIsDiscarded() async throws {
        let fp = DocumentFingerprint(
            contentSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            fileByteCount: 2048,
            format: .epub
        )
        let locSuccess = try #require(Locator.validated(bookFingerprint: fp, href: "ch1.xhtml"))
        let locFailed = try #require(Locator.validated(bookFingerprint: fp, href: "ch2.xhtml"))

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
        #expect(collected.first?.locator?.href == "ch1.xhtml")
        #expect(collected.first?.snippet.contains("fetch_success") == true)

        let citations = collected.compactMap { $0.toChatCitation() }
        #expect(citations.count == 1)
        #expect(citations.first?.locator?.href == "ch1.xhtml")
    }

    // MARK: - 4. Multi-Turn Session Reuse, Reader Token Isolation & Conversation Isolation

    @Test func sameReaderSessionReusesInstanceWhileDifferentTokenOrConversationGetsNewSession() async throws {
        let box = SessionBox()

        let backend = AppleFoundationModelsBackend(
            availability: AppleFoundationModelsAvailability(state: .available),
            sessionFactory: { instructions, tools in
                let s = TestMockSession(instructions: instructions, tools: tools)
                box.sessions.append(s)
                return s
            }
        )

        let tokenA = UUID()
        let tokenB = UUID()
        let sessionID_A = AIDocumentSessionID(fingerprintKey: "book-shared", readerToken: tokenA)
        let sessionID_B = AIDocumentSessionID(fingerprintKey: "book-shared", readerToken: tokenB)

        // Turn 1 for Reader A, Conversation 1
        _ = try await backend.executeTurn(
            systemPrompt: "System",
            prompt: "Turn 1 for A conv 1",
            documentSessionID: sessionID_A,
            turnID: "turn-1",
            conversationID: "conv-1"
        )
        #expect(box.sessions.count == 1)
        let sessionAConv1 = box.sessions[0]
        #expect(sessionAConv1.respondCount == 1)

        // Turn 2 for Reader A, Conversation 1 (must reuse sessionAConv1)
        _ = try await backend.executeTurn(
            systemPrompt: "System",
            prompt: "Turn 2 for A conv 1",
            documentSessionID: sessionID_A,
            turnID: "turn-2",
            conversationID: "conv-1"
        )
        #expect(box.sessions.count == 1)
        #expect(sessionAConv1.respondCount == 2)

        // Turn 1 for Reader A, Conversation 2 (same reader, new conversation -> distinct session!)
        _ = try await backend.executeTurn(
            systemPrompt: "System",
            prompt: "Turn 1 for A conv 2",
            documentSessionID: sessionID_A,
            turnID: "turn-3",
            conversationID: "conv-2"
        )
        #expect(box.sessions.count == 2)
        let sessionAConv2 = box.sessions[1]
        #expect(sessionAConv2 !== sessionAConv1)
        #expect(sessionAConv2.respondCount == 1)

        // Turn 1 for Reader B on the SAME book (different reader token -> distinct session!)
        _ = try await backend.executeTurn(
            systemPrompt: "System",
            prompt: "Turn 1 for B",
            documentSessionID: sessionID_B,
            turnID: "turn-4",
            conversationID: "conv-1"
        )
        #expect(box.sessions.count == 3)
        let sessionB = box.sessions[2]
        #expect(sessionB !== sessionAConv1)
        #expect(sessionB !== sessionAConv2)
        #expect(sessionB.respondCount == 1)
    }

    // MARK: - 5. Routed AIChatViewModel Citations & Conversation Thread Lifecycle

    @MainActor
    @Test func routedChatViewModelPreservesToolCitationsAndIsolatesConversationsAcrossPersistAndSwitch() async throws {
        final class InMemoryChatSessionStore: ChatSessionPersisting, @unchecked Sendable {
            private var records: [UUID: ChatSessionRecord] = [:]
            private var order: [UUID] = []

            func fetchChatSessionSummaries(forBookWithKey bookFingerprintKey: String) async throws -> [ChatSessionSummary] {
                order.compactMap { id in
                    guard let rec = records[id], rec.bookFingerprintKey == bookFingerprintKey else { return nil }
                    return ChatSessionSummary(
                        id: rec.sessionId,
                        title: rec.title,
                        updatedAt: rec.updatedAt,
                        messageCount: rec.messages.count
                    )
                }
            }

            func fetchChatSession(sessionId: UUID) async throws -> ChatSessionRecord? {
                records[sessionId]
            }

            func createChatSession(bookFingerprintKey: String, title: String, messages: [ChatMessage]) async throws -> ChatSessionRecord {
                let id = UUID()
                let now = Date()
                let record = ChatSessionRecord(
                    sessionId: id,
                    bookFingerprintKey: bookFingerprintKey,
                    title: title,
                    createdAt: now,
                    updatedAt: now,
                    messages: messages
                )
                records[id] = record
                order.insert(id, at: 0)
                return record
            }

            func updateChatSession(sessionId: UUID, messages: [ChatMessage], title: String?) async throws -> ChatSessionRecord {
                let existing = records[sessionId]
                let updated = ChatSessionRecord(
                    sessionId: sessionId,
                    bookFingerprintKey: existing?.bookFingerprintKey ?? "",
                    title: title ?? existing?.title ?? "Chat",
                    createdAt: existing?.createdAt ?? Date(),
                    updatedAt: Date(),
                    messages: messages
                )
                records[sessionId] = updated
                order.removeAll { $0 == sessionId }
                order.insert(sessionId, at: 0)
                return updated
            }

            func renameChatSession(sessionId: UUID, title: String) async throws {
                guard let existing = records[sessionId] else { return }
                records[sessionId] = ChatSessionRecord(
                    sessionId: sessionId,
                    bookFingerprintKey: existing.bookFingerprintKey,
                    title: title,
                    createdAt: existing.createdAt,
                    updatedAt: Date(),
                    messages: existing.messages
                )
            }

            func deleteChatSession(sessionId: UUID) async throws {
                records.removeValue(forKey: sessionId)
                order.removeAll { $0 == sessionId }
            }
        }

        final class RecordingTurnRouter: AIAgentTurnExecuting, @unchecked Sendable {
            var nextResult: AgenticResult
            var recordedConversationIDs: [String?] = []

            init(nextResult: AgenticResult) {
                self.nextResult = nextResult
            }

            func executeTurn(
                prompt: String,
                systemPrompt: String,
                contextText: String?,
                registry: AIToolRegistry,
                documentSessionID: AIDocumentSessionID?,
                turnID: String,
                conversationID: String?
            ) async throws -> AgenticResult {
                recordedConversationIDs.append(conversationID)
                return nextResult
            }
        }

        let fp = DocumentFingerprint(
            contentSHA256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
            fileByteCount: 8192,
            format: .epub
        )
        let preSendLocator = try #require(Locator.validated(bookFingerprint: fp, href: "ch1.xhtml"))
        let toolLocator = try #require(Locator.validated(bookFingerprint: fp, href: "ch9.xhtml"))

        let preSendCitation = ChatCitation(
            sourceKind: .scope,
            label: "Current Chapter",
            locator: preSendLocator
        )
        let toolProvenance = AISourceProvenance(
            bookFingerprintKey: fp.canonicalKey,
            bookTitle: "Test EPUB",
            locator: toolLocator,
            sourceLabel: "Chapter 9",
            chapterTitle: "Chapter 9",
            href: "ch9.xhtml",
            snippet: "Tool retrieved chapter 9",
            retrievalMethod: .semanticSearch,
            score: 0.99
        )
        let toolCitation = try #require(toolProvenance.toChatCitation())

        let store = InMemoryChatSessionStore()
        let spyTool = ContextSpyTool(name: "search_current_book")
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        flags.setOverride(true, for: .agenticTools)
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: KeychainService(serviceIdentifier: "com.vreader.test.\(UUID().uuidString)")
        )
        let vm = AIChatViewModel(
            aiService: service,
            bookFingerprint: fp,
            featureFlags: flags,
            agenticRegistry: AIToolRegistry([spyTool]),
            chatSessionStore: store
        )
        vm.documentSessionID = AIDocumentSessionID(fingerprintKey: fp.canonicalKey, readerToken: UUID())
        vm.pendingCitations = [preSendCitation]

        let router = RecordingTurnRouter(
            nextResult: AgenticResult(
                finalText: "Answer with tool citation",
                usedTools: true,
                citations: [toolCitation],
                sourceProvenances: [toolProvenance]
            )
        )
        vm.turnRouter = router

        // Turn 1 (before persistence sets activeSessionId):
        await vm.sendMessage("First question in Conv 1")
        let firstAssistant = try #require(vm.messages.last)
        #expect(firstAssistant.citations == [toolCitation])
        #expect(firstAssistant.sourceProvenance == [toolProvenance])
        let conv1SessionID = try #require(vm.activeSessionId)
        let turn1ConvID = try #require(router.recordedConversationIDs.first ?? nil)

        // Turn 2 in the SAME conversation (after activeSessionId is set):
        // Also verify fallback to citationSnapshot when result.citations is empty.
        router.nextResult = AgenticResult(
            finalText: "Answer without tool citation",
            usedTools: false,
            citations: [],
            sourceProvenances: []
        )
        await vm.sendMessage("Second question in Conv 1")
        let secondAssistant = try #require(vm.messages.last)
        #expect(secondAssistant.citations == [preSendCitation])
        let turn2ConvID = try #require(router.recordedConversationIDs.last ?? nil)
        #expect(turn2ConvID == turn1ConvID, "Turn 1 (unsaved) and Turn 2 (saved) in the same conversation must use the same conversationID")

        // Start a new conversation -> must get a fresh conversationID
        await vm.newConversation()
        await vm.sendMessage("First question in Conv 2")
        let turn3ConvID = try #require(router.recordedConversationIDs.last ?? nil)
        #expect(turn3ConvID != turn1ConvID, "newConversation() must isolate into a distinct conversationID")

        // Switch back to Conversation 1 -> must restore Conv 1's conversationID
        await vm.switchToSession(conv1SessionID)
        await vm.sendMessage("Third question in Conv 1")
        let turn4ConvID = try #require(router.recordedConversationIDs.last ?? nil)
        #expect(turn4ConvID == turn1ConvID, "switchToSession must restore the conversation's session key")
    }

    // MARK: - 6. Cancellation Safety

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
