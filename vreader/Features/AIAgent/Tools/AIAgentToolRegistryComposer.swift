// Purpose: Additive composer populating Feature #177 semantic, OCR, mutation, and MCP tools into AIToolRegistry.
// Keeps AgenticToolRegistryBuilder minimal as an upstream integration seam.

import Foundation

enum AIAgentToolRegistryComposer {

    /// Composes Feature #177 tools into an existing array of tools.
    static func compose(
        into tools: inout [any AITool],
        currentBook: DocumentFingerprint?,
        authorizationGate: AIAgentToolExecutionGate,
        readerContext: (any AIReaderToolContextProviding)? = nil,
        annotationCoordinator: AIAnnotationMutationCoordinator? = nil,
        semanticSearchService: SemanticSearchService? = nil,
        ocrService: (any PDFOCRServicing)? = nil,
        pdfFacade: (any AIPDFDocumentFacading)? = nil,
        mcpAdapters: [MCPToolAdapter] = []
    ) {
        // 1. Semantic Search Tools
        if let semantic = semanticSearchService {
            tools.append(SemanticSearchLibraryTool(
                service: semantic,
                authorizationGate: authorizationGate
            ))
            if let currentBook, let readerContext {
                _ = currentBook
                tools.append(SemanticSearchCurrentBookTool(
                    service: semantic,
                    context: readerContext,
                    authorizationGate: authorizationGate
                ))
            }
        }

        // 2. Annotation & Mutation Tools
        if let coordinator = annotationCoordinator, let readerContext {
            tools.append(CreateNoteTool(coordinator: coordinator, context: readerContext, authorizationGate: authorizationGate))
            tools.append(EditNoteTool(coordinator: coordinator, context: readerContext, authorizationGate: authorizationGate))
            tools.append(DeleteNoteTool(coordinator: coordinator, context: readerContext, authorizationGate: authorizationGate))

            tools.append(AddHighlightTool(coordinator: coordinator, context: readerContext, authorizationGate: authorizationGate))
            tools.append(UpdateHighlightTool(coordinator: coordinator, context: readerContext, authorizationGate: authorizationGate))
            tools.append(RemoveHighlightTool(coordinator: coordinator, context: readerContext, authorizationGate: authorizationGate))

            tools.append(AddBookmarkTool(coordinator: coordinator, context: readerContext, authorizationGate: authorizationGate))
            tools.append(UpdateBookmarkTool(coordinator: coordinator, context: readerContext, authorizationGate: authorizationGate))
            tools.append(RemoveBookmarkTool(coordinator: coordinator, context: readerContext, authorizationGate: authorizationGate))
        }

        // 3. OCR Text Extraction Tool
        if let ocr = ocrService, let facade = pdfFacade, let readerContext {
            tools.append(ExtractPageTextTool(
                ocrService: ocr,
                facade: facade,
                context: readerContext,
                authorizationGate: authorizationGate
            ))
        }

        // 4. MCP Dynamic External Tool Adapters
        for adapter in mcpAdapters {
            tools.append(adapter)
        }
    }
}
