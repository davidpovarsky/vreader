// Purpose: Central production runtime and dependency assembler for Feature #177 AI Agent.
// Assembles connected confirmation broker, exact reader sessions, real mutations, semantic ANN,
// live PDF OCR, real MCP connections, and Apple Foundation Models / provider turn router.

import Foundation
import OSLog

@MainActor
final class AIAgentProductionRuntime {
    private static let log = Logger(subsystem: "com.vreader.app", category: "AIAgentProductionRuntime")

    static let shared = AIAgentProductionRuntime()

    private let preferencesStore: any AIAgentPreferencesStoring
    private let capabilityStore: AIAgentCapabilityPreferencesStore
    private let confirmationBroker: AIActionConfirmationBroker
    private let semanticModelManager: AISemanticModelManager
    private let mcpProfileStore: MCPServerProfileStore
    private let mcpClientManager: MCPClientManager

    // Shared persistent stores for semantic indexing & ANN search
    private let sharedIndexStore = SemanticIndexStore()
    private let sharedMetadataStore = SemanticIndexMetadataStore()
    private var semanticIndexCoordinator: SemanticIndexCoordinator?
    private var activeSemanticSearchService: SemanticSearchService?

    init(
        preferencesStore: any AIAgentPreferencesStoring = AIAgentPreferencesStore.shared,
        capabilityStore: AIAgentCapabilityPreferencesStore = .shared,
        confirmationBroker: AIActionConfirmationBroker = .shared,
        semanticModelManager: AISemanticModelManager = .shared,
        mcpProfileStore: MCPServerProfileStore = .shared,
        mcpClientManager: MCPClientManager = .shared
    ) {
        self.preferencesStore = preferencesStore
        self.capabilityStore = capabilityStore
        self.confirmationBroker = confirmationBroker
        self.semanticModelManager = semanticModelManager
        self.mcpProfileStore = mcpProfileStore
        self.mcpClientManager = mcpClientManager
    }

    /// Assembles the complete production tool registry for the given reader session.
    func makeReaderToolRegistry(
        currentBook: DocumentFingerprint,
        readerToken: UUID,
        readerContext: any AIReaderToolContextProviding,
        library: any LibraryPersisting,
        annotationStores: (any AnnotationPersisting & HighlightPersisting & BookmarkPersisting)?
    ) async throws -> AIToolRegistry {
        let sessionID = AIDocumentSessionID(
            fingerprintKey: currentBook.canonicalKey,
            readerToken: readerToken
        )

        // 1. Connected confirmation gate scoped to shared broker
        let gate = AIAgentToolExecutionGate.productionConnected(
            broker: confirmationBroker,
            preferencesStore: preferencesStore
        )

        // 2. Annotation mutation coordinator
        let mutationCoordinator: AIAnnotationMutationCoordinator?
        let annotationReader: (any AIAnnotationReading)?
        if let stores = annotationStores {
            mutationCoordinator = AIAnnotationMutationCoordinator(
                annotationPersisting: stores,
                highlightPersisting: stores,
                bookmarkPersisting: stores
            )
            annotationReader = AIAnnotationReadStoreAdapter(
                annotationStore: stores,
                highlightStore: stores,
                bookmarkStore: stores
            )
        } else {
            mutationCoordinator = nil
            annotationReader = nil
        }

        let capabilities = await capabilityStore.load()

        // 3. Real semantic runtime with shared stores and lazy load
        var semanticSearchService: SemanticSearchService? = nil
        let isModelInstalled = await semanticModelManager.state.isInstalled
        if capabilities.isSemanticSearchEnabled && isModelInstalled {
            let isReadyBefore = await semanticModelManager.state.isReady
            if !isReadyBefore {
                try? await semanticModelManager.ensureLoaded()
            }
            if await semanticModelManager.state.isReady {
                let embeddingService = await semanticModelManager.loadedEmbeddingService ?? MLXE5EmbeddingService()
                let indexStore = self.sharedIndexStore
                let metadataStore = self.sharedMetadataStore
                let coordinator = SemanticIndexCoordinator(
                    embeddingService: embeddingService,
                    metadataStore: metadataStore,
                    indexStore: indexStore
                )
                self.semanticIndexCoordinator = coordinator
                let searchService = SemanticSearchService(
                    embeddingService: embeddingService,
                    metadataStore: metadataStore,
                    indexStore: indexStore
                )
                self.activeSemanticSearchService = searchService
                semanticSearchService = searchService

                // Index current book in background if missing or stale
                if let provider = AIDocumentProviderRegistry.shared.resolve(session: sessionID) {
                    Task { [coordinator, metadataStore, currentBook] in
                        let existing = await metadataStore.fetchMetadata(forBook: currentBook.canonicalKey)
                        if existing == nil || !existing!.isCompatible(withActiveModel: AISemanticModelManager.modelIdentifier, dimension: embeddingService.dimension) {
                            if let chunks = try? await provider.chunks() {
                                try? await coordinator.indexBook(fingerprintKey: currentBook.canonicalKey, chunks: chunks)
                                NotificationCenter.default.post(name: .aiAgentConfigurationDidChange, object: nil)
                            }
                        }
                    }
                }
            }
        }

        // 4. Real PDF OCR runtime (if enabled and live PDF OCR source available)
        var ocrService: (any PDFOCRServicing)? = nil
        var pdfFacade: (any AIPDFDocumentFacading)? = nil
        if capabilities.isOCREnabled,
           let document = await readerContext.resolveDocument(),
           document.snapshot.format == .pdf,
           let provider = AIDocumentProviderRegistry.shared.resolve(session: sessionID) as? AIPDFOCRSourceProviding {
            ocrService = PDFOCRService()
            pdfFacade = provider.ocrFacade
        }

        // 5. Discover real MCP tool adapters
        var mcpAdapters: [MCPToolAdapter] = []
        let discoveredTools = await mcpClientManager.discoverEnabledTools()
        for discovered in discoveredTools {
            let toolName = MCPToolNameMapper.map(
                serverPrefix: discovered.profile.name,
                originalToolName: discovered.tool.name
            )
            let mappedDefinition = ToolDefinition(
                name: toolName,
                description: discovered.tool.description,
                inputSchema: discovered.tool.inputSchema
            )
            let adapter = MCPToolAdapter(
                profileID: discovered.profile.id,
                serverName: discovered.profile.name,
                originalToolName: discovered.tool.name,
                definition: mappedDefinition,
                clientManager: mcpClientManager,
                authorizationGate: gate,
                readerSessionID: sessionID
            )
            mcpAdapters.append(adapter)
        }

        // 6. Build the live registry with all real dependencies injected
        return try await AgenticToolRegistryBuilder.buildLive(
            currentBook: currentBook,
            library: library,
            readerContext: readerContext,
            authorizationGate: gate,
            annotationStore: annotationReader,
            navigationRouter: NotificationAIReaderNavigationRouter(),
            annotationCoordinator: mutationCoordinator,
            semanticSearchService: semanticSearchService,
            ocrService: ocrService,
            pdfFacade: pdfFacade,
            mcpAdapters: mcpAdapters
        )
    }

    /// Assembles the execution router for chat turns.
    func makeTurnRouter(
        aiService: AIService,
        executionGate: AIAgentToolExecutionGate
    ) -> AIAgentTurnRouter {
        let cloud = CloudProviderTurnExecutor(aiService: aiService)
        let apple = AppleFoundationModelsTurnExecutor(executionGate: executionGate)
        return AIAgentTurnRouter(
            cloudExecutor: cloud,
            appleExecutor: apple,
            backendChoice: {
                AIAgentCapabilityPreferencesStore.currentBackendChoice()
            }
        )
    }
}
