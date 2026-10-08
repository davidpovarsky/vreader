// Purpose: Central production runtime and dependency assembler for Feature #177 AI Agent.
// Assembles connected confirmation broker, exact reader sessions, real mutations, semantic ANN,
// live PDF OCR, real MCP connections, and Apple Foundation Models / provider turn router.

import Foundation
import OSLog

enum AIAgentSemanticRuntimeStatus: Sendable, Equatable {
    case disabled
    case modelMissing
    case loadingModel
    case indexing(bookKey: String, progress: Double)
    case ready
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

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
    private(set) var libraryIndexer: AIAgentSemanticLibraryIndexer?
    private(set) var semanticRuntimeStatus: AIAgentSemanticRuntimeStatus = .disabled
    private var activeIndexingBookKeys: Set<String> = []

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

    /// Returns the long-lived coordinator or initializes it once.
    func getOrInitSemanticCoordinator(embeddingService: any SemanticEmbeddingProviding) -> SemanticIndexCoordinator {
        if let existing = self.semanticIndexCoordinator {
            return existing
        }
        let coordinator = SemanticIndexCoordinator(
            embeddingService: embeddingService,
            metadataStore: self.sharedMetadataStore,
            indexStore: self.sharedIndexStore
        )
        self.semanticIndexCoordinator = coordinator
        return coordinator
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

        // 3. Real semantic runtime with long-lived stores and explicit status
        var semanticSearchService: SemanticSearchService? = nil
        let isModelInstalled = await semanticModelManager.state.isInstalled
        if capabilities.isSemanticSearchEnabled && isModelInstalled {
            let isReadyBefore = await semanticModelManager.state.isReady
            if !isReadyBefore {
                self.semanticRuntimeStatus = .loadingModel
                do {
                    try await semanticModelManager.ensureLoaded()
                } catch {
                    self.semanticRuntimeStatus = .failed("Failed to load model: \(error.localizedDescription)")
                    Self.log.error("Failed to load semantic model: \(error.localizedDescription)")
                }
            }

            if await semanticModelManager.state.isReady {
                let embeddingService = await semanticModelManager.loadedEmbeddingService ?? MLXE5EmbeddingService()
                let coordinator = getOrInitSemanticCoordinator(embeddingService: embeddingService)

                if self.activeSemanticSearchService == nil {
                    self.activeSemanticSearchService = SemanticSearchService(
                        embeddingService: embeddingService,
                        metadataStore: self.sharedMetadataStore,
                        indexStore: self.sharedIndexStore
                    )
                }
                semanticSearchService = self.activeSemanticSearchService

                // Initialize library indexer if needed
                if self.libraryIndexer == nil {
                    let indexer = AIAgentSemanticLibraryIndexer(
                        library: library,
                        coordinator: coordinator,
                        metadataStore: self.sharedMetadataStore,
                        indexStore: self.sharedIndexStore,
                        embeddingService: embeddingService,
                        ocrService: (capabilities.isOCREnabled ? PDFOCRService() : nil)
                    )
                    self.libraryIndexer = indexer
                    Task { [indexer] in
                        await indexer.startIndexing(forceRebuild: false)
                    }
                }

                // Index current book in background if missing or stale (one job per book guaranteed)
                let currentBookKey = currentBook.canonicalKey
                if let provider = AIDocumentProviderRegistry.shared.resolve(session: sessionID),
                   !activeIndexingBookKeys.contains(currentBookKey) {
                    activeIndexingBookKeys.insert(currentBookKey)
                    Task { [weak self, coordinator, metadataStore = self.sharedMetadataStore] in
                        let existing = await metadataStore.fetchMetadata(forBook: currentBookKey)
                        let isCompatible = existing?.isCompatible(
                            withActiveModel: AISemanticModelManager.modelIdentifier,
                            dimension: embeddingService.dimension
                        ) ?? false

                        if !isCompatible {
                            self?.semanticRuntimeStatus = .indexing(bookKey: currentBookKey, progress: 0.0)
                            do {
                                let chunks = try await provider.chunks()
                                try await coordinator.indexBook(fingerprintKey: currentBookKey, chunks: chunks)
                                self?.semanticRuntimeStatus = .ready
                                NotificationCenter.default.post(name: .aiAgentConfigurationDidChange, object: nil)
                            } catch {
                                self?.semanticRuntimeStatus = .failed("Indexing failed: \(error.localizedDescription)")
                                Self.log.error("Semantic indexing failed for \(currentBookKey): \(error.localizedDescription)")
                            }
                        } else {
                            self?.semanticRuntimeStatus = .ready
                        }
                        self?.activeIndexingBookKeys.remove(currentBookKey)
                    }
                }
            } else {
                if case .failed = self.semanticRuntimeStatus {
                    // Retain failed status
                } else {
                    self.semanticRuntimeStatus = .modelMissing
                }
            }
        } else {
            self.semanticRuntimeStatus = capabilities.isSemanticSearchEnabled ? .modelMissing : .disabled
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
