// Purpose: Corrective pass unit tests for Feature #177 Requirements 9-18.
// Validates MCP auth/auto-connect, Apple tool calling/mode routing, highlight anchor validation, provenance isolation, and staged tap sinks.

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@MainActor
private final class MockHighlightContext: AIReaderToolContextProviding {
    let bookTitle: String = "Anchor Book"
    let fingerprint: DocumentFingerprint
    let sessionID: AIDocumentSessionID
    var stubbedDocument: AILiveReaderDocument?

    init(fingerprint: DocumentFingerprint) {
        self.fingerprint = fingerprint
        self.sessionID = AIDocumentSessionID(fingerprintKey: fingerprint.canonicalKey, readerToken: UUID())
        let chunk = AIDocumentChunk(
            unit: .chapter(title: "Ch 1"),
            locator: Locator.validated(bookFingerprint: fingerprint, href: "ch1.xhtml")!,
            text: "The golden passage to highlight.",
            isSafeCurrentSection: true,
            isSafeBookSoFar: true,
            isAheadOfReader: false
        )
        let snapshot = AIDocumentSnapshot(bookFingerprint: fingerprint, format: .epub, chunks: [chunk])
        self.stubbedDocument = AILiveReaderDocument(snapshot: snapshot, chunks: [chunk])
    }

    func resolveDocument() async -> AILiveReaderDocument? { stubbedDocument }
    func tableOfContents() async -> [AIDocumentTOCSummaryItem] { [] }
}

private final class MockHighlightPersistence: AnnotationPersisting, HighlightPersisting, BookmarkPersisting, @unchecked Sendable {
    var createdHighlights: [(key: String, text: String, color: String)] = []

    func addHighlight(locator: Locator, anchor: AnnotationAnchor?, selectedText: String, color: String, note: String?, toBookWithKey key: String) async throws -> HighlightRecord {
        createdHighlights.append((key: key, text: selectedText, color: color))
        return HighlightRecord(highlightId: UUID(), locator: locator, anchor: anchor, profileKey: key, selectedText: selectedText, color: color, note: note, createdAt: Date(), updatedAt: Date())
    }
    func addHighlight(locator: Locator, selectedText: String, color: String, note: String?, toBookWithKey key: String) async throws -> HighlightRecord {
        try await addHighlight(locator: locator, anchor: nil, selectedText: selectedText, color: color, note: note, toBookWithKey: key)
    }
    func removeHighlight(highlightId: UUID) async throws {}
    func updateHighlightNote(highlightId: UUID, note: String?) async throws {}
    func updateHighlightColor(highlightId: UUID, color: String) async throws {}
    func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] { [] }
    func addAnnotation(locator: Locator, content: String, toBookWithKey key: String) async throws -> AnnotationRecord {
        AnnotationRecord(annotationId: UUID(), locator: locator, profileKey: key, content: content, createdAt: Date(), updatedAt: Date())
    }
    func removeAnnotation(annotationId: UUID) async throws {}
    func updateAnnotation(annotationId: UUID, content: String) async throws {}
    func fetchAnnotations(forBookWithKey key: String) async throws -> [AnnotationRecord] { [] }
    func addBookmark(locator: Locator, title: String?, toBookWithKey key: String) async throws -> BookmarkRecord {
        BookmarkRecord(bookmarkId: UUID(), locator: locator, profileKey: key, title: title, createdAt: Date(), updatedAt: Date())
    }
    func removeBookmark(bookmarkId: UUID) async throws {}
    func fetchBookmarks(forBookWithKey key: String) async throws -> [BookmarkRecord] { [] }
    func isBookmarked(locator: Locator, forBookWithKey key: String) async throws -> Bool { false }
    func updateBookmarkTitle(bookmarkId: UUID, title: String?) async throws {}
}

@Suite("Feature177CorrectivePassTests — MCP, Apple & Mutation (Req 9-18)")
struct Feature177CorrectivePassMCPAndAppleTests {

    // MARK: - 9. MCP Bearer Auth URLSessionConfiguration Binding
    @Test func mcpSecretStoreBindsToProfileAndHost() throws {
        let store = MCPSecretStore(serviceName: "test-mcp-secrets-\(UUID().uuidString)")
        let profileID = UUID()
        let endpoint = try #require(URL(string: "https://mcp.example.com/sse"))

        try store.saveToken("secret-token-xyz", for: profileID, endpointURL: endpoint)
        let fetched = try store.token(for: profileID, endpointURL: endpoint)
        #expect(fetched == "secret-token-xyz")

        // Different host returns nil
        let otherEndpoint = try #require(URL(string: "https://other.example.com/sse"))
        #expect(try store.token(for: profileID, endpointURL: otherEndpoint) == nil)

        try store.deleteToken(for: profileID, endpointURL: endpoint)
        #expect(try store.token(for: profileID, endpointURL: endpoint) == nil)
    }

    // MARK: - 10. MCP OAuth Auth with Client ID & Redirect URI
    @Test func mcpOAuthCoordinatorPreparesAuthRequestWithClientID() throws {
        let secretStore = MCPSecretStore(serviceName: "test-oauth-\(UUID().uuidString)")
        let coordinator = MCPOAuthCoordinator(secretStore: secretStore)
        let profileID = UUID()
        let authURL = try #require(URL(string: "https://auth.example.com/authorize"))
        let tokenURL = try #require(URL(string: "https://auth.example.com/token"))

        let url = try coordinator.startOAuth(
            profileID: profileID,
            authorizationURL: authURL,
            tokenURL: tokenURL,
            clientID: "vreader-client-id",
            redirectURI: "vreader://oauth-callback",
            scopes: ["tools:read", "tools:call"]
        )

        let fullURL = url.absoluteString
        #expect(fullURL.contains("client_id=vreader-client-id"))
        #expect(fullURL.contains("redirect_uri=vreader%3A%2F%2Foauth-callback") || fullURL.contains("redirect_uri=vreader://oauth-callback"))
        #expect(fullURL.contains("response_type=code"))
        #expect(fullURL.contains("state="))
    }

    // MARK: - 11. MCP Auto-Connect on Startup
    @Test func mcpClientManagerAutoConnectsEnabledProfiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MCPServerProfileStore(storageDirectory: tempDir)
        let profile = MCPServerProfile(
            name: "AutoServer",
            endpointURL: URL(string: "https://mcp.test/mcp")!,
            isEnabled: true
        )
        try await store.saveProfile(profile)

        let mockTool = ToolDefinition(name: "test_mcp_tool", description: "A test tool")
        let mgr = MCPClientManager(
            profileStore: store,
            secretStore: MCPSecretStore(),
            connectionFactory: { p in MockMCPConnection(profile: p, mockTools: [mockTool]) }
        )

        let discovered = await mgr.discoverEnabledTools()
        #expect(discovered.count == 1)
        #expect(discovered.first?.profile.id == profile.id)
        #expect(discovered.first?.tool.name == "test_mcp_tool")
        let status = await mgr.status(for: profile.id)
        #expect(status.isConnected == true)
    }

    // MARK: - 12. Apple Native Tool Dispatch Adapter
    @Test func appleFoundationModelsToolAdapterDispatchesNativeCall() async throws {
        struct DummyTool: AITool {
            var definition: ToolDefinition {
                ToolDefinition(
                    name: "dummy_calc",
                    description: "Returns doubled number",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "number": .object(["type": .string("number")])
                        ])
                    ])
                )
            }
            func run(_ input: JSONValue) async -> ToolResult {
                guard case .object(let dict) = input, case .number(let n)? = dict["number"] else {
                    return ToolResult(toolUseID: "call_1", content: "Missing number", isError: true)
                }
                return ToolResult(toolUseID: "call_1", content: "Doubled: \(Int(n * 2))", isError: false)
            }
        }

        let adapter = AppleFoundationModelsToolAdapter(tools: [DummyTool()])
        #expect(adapter.definitions.count == 1)
        #expect(adapter.definitions[0].name == "dummy_calc")

        let result = await adapter.executeToolCall(name: "dummy_calc", arguments: "{\"number\": 21}")
        #expect(result == "Doubled: 42")
    }

    // MARK: - 13. Apple Mode & Consent Routing
    @Test func appleBackendConfigResolvesModeAndConsent() {
        let prefs = AIAgentCapabilityPreferences(
            foundationModelMode: .onDevice,
            isPCCConsentGranted: false
        )
        let policy = AppleFoundationModelsPolicy(
            mode: prefs.foundationModelMode,
            userConsentedToPCC: prefs.isPCCConsentGranted
        )
        #expect(policy.mode == .onDevice)
        #expect(!policy.isPCCConsentGranted)
        #expect(!policy.permitsPrivateCloudCompute)
    }

    // MARK: - 14. Apple Multi-Turn Context Persistence
    @Test func appleFoundationModelsSessionMaintainsTurns() {
        let session = AppleFoundationModelsBackend.SessionTranscript(sessionID: UUID().uuidString)
        #expect(session.turns.isEmpty)
        session.append(role: "user", text: "What is chapter 1 about?")
        session.append(role: "assistant", text: "Chapter 1 introduces the protagonist.")
        #expect(session.turns.count == 2)
        #expect(session.turns[0].text == "What is chapter 1 about?")
        #expect(session.turns[1].text == "Chapter 1 introduces the protagonist.")
    }

    // MARK: - 15. Highlight Anchor Validation
    @Test @MainActor func addHighlightToolRejectsUnanchoredOrWrongBookLocator() async {
        let fp = DocumentFingerprint(scheme: "test", value: "book-anchor-1")
        let context = MockHighlightContext(fingerprint: fp)
        let persistence = MockHighlightPersistence()
        let coordinator = AIAnnotationMutationCoordinator(
            annotationPersisting: persistence,
            highlightPersisting: persistence,
            bookmarkPersisting: persistence
        )

        let store = InMemoryAIAgentPreferencesStore()
        store.preferences.permissions[.writeAnnotations] = .allow
        let gate = AIAgentToolExecutionGate(preferencesStore: store, broker: AIActionConfirmationBroker(preferencesStore: store), confirmationAvailability: .brokerConnected)
        let tool = AddHighlightTool(coordinator: coordinator, context: context, authorizationGate: gate)

        // 1. Rejects unanchored text-only call
        let unanchoredRes = await tool.run(.object(["text": .string("Arbitrary model hallucination")]))
        #expect(unanchoredRes.isError)
        #expect(unanchoredRes.content.contains("A resolvable source anchor"))

        // 2. Rejects wrong-book locator
        let wrongFP = DocumentFingerprint(scheme: "test", value: "wrong-book")
        let wrongLocator = Locator.validated(bookFingerprint: wrongFP, href: "ch1.xhtml", textQuote: "Quote")!
        let wrongJSON = String(data: (try? JSONEncoder().encode(wrongLocator)) ?? Data(), encoding: .utf8) ?? "{}"
        let wrongRes = await tool.run(.object(["text": .string("Passage"), "locator_json": .string(wrongJSON)]))
        #expect(wrongRes.isError)
        #expect(wrongRes.content.contains("does not match current book fingerprint"))

        // 3. Accepts valid anchored locator
        let validLocator = Locator.validated(bookFingerprint: fp, href: "ch1.xhtml", textQuote: "The golden passage")!
        let validJSON = String(data: (try? JSONEncoder().encode(validLocator)) ?? Data(), encoding: .utf8) ?? "{}"
        let successRes = await tool.run(.object(["text": .string("The golden passage"), "locator_json": .string(validJSON)]))
        #expect(!successRes.isError)
        #expect(successRes.content.contains("Added highlight"))
        #expect(persistence.createdHighlights.count == 1)
    }

    // MARK: - 16. External Provenance No-Locator Behavior
    @Test func externalProvenanceNeverFabricatesLocalLocator() {
        let prov = AISourceProvenance(
            bookFingerprintKey: "mcp-service",
            snippet: "Server response text",
            retrievalMethod: .mcpExternal,
            mcpServerName: "RemoteTool"
        )
        #expect(prov.locator == nil)
        #expect(prov.toChatCitation() == nil)
    }

    // MARK: - 17. Failed-Tool Provenance Exclusion
    @Test func failedToolCallDiscardsStagedProvenance() async {
        let sink = ProvenanceTapSink()
        let callID = "call-failing-tool"

        let prov = AISourceProvenance(
            bookFingerprintKey: "bookA",
            snippet: "Speculative hit before tool threw error",
            retrievalMethod: .semanticSearch
        )

        await sink.stage(prov, for: callID)
        let initial = await sink.allSources()
        #expect(initial.isEmpty, "Staged source must not be visible in allSources before commit.")

        // Tool execution encounters error -> discard
        await sink.discardSources(for: callID)
        let afterDiscard = await sink.allSources()
        #expect(afterDiscard.isEmpty, "Discarded source must not be committed.")

        // Successful call -> commit
        let successCallID = "call-success-tool"
        await sink.stage(prov, for: successCallID)
        await sink.commitSources(for: successCallID)
        let final = await sink.allSources()
        #expect(final.count == 1)
        #expect(final.first?.id == prov.id)
    }

    // MARK: - 18. Expanded No-Fake-Completion Guard
    @Test func pdfOCRServiceFailsGracefullyOnEmptyScannedPages() async throws {
        let service = PDFOCRService()
        let blankImage = CGImage(
            width: 10, height: 10,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 40,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(repeating: 255, count: 400) as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!

        do {
            _ = try await service.performOCR(on: blankImage, pageIndex: 0)
            Issue.record("Expected empty text error for completely blank image")
        } catch {
            // Expected error
            #expect(error is PDFOCRError)
        }
    }
}
