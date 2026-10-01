// Purpose: Model-facing tools for current-book and library semantic and hybrid search.
// Fully gated by AIAgentToolExecutionGate and spoiler-safe against the active reader boundary.

import Foundation

struct SemanticSearchCurrentBookTool: AIContextualTool {
    static let toolName = "semantic_search_current_book"
    let service: SemanticSearchService
    let context: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        service: SemanticSearchService,
        context: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 8_000
    ) {
        self.service = service
        self.context = context
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Search the current book using meaning and semantics instead of exact keywords.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("The semantic concept or question to search for in the book.")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        await run(input, context: AIToolExecutionContext())
    }

    func run(_ input: JSONValue, context: AIToolExecutionContext) async -> ToolResult {
        guard case .object(let dict) = input,
              case .string(let query)? = dict["query"],
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AIReaderToolOutput.boundedResult(
                "A non-empty query parameter is required.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        if let denied = await AICurrentReaderToolSupport.authorize(
            toolName: Self.toolName,
            action: "Semantic search in the current book",
            context: self.context,
            gate: authorizationGate,
            maxBytes: maxContentBytes
        ) { return denied }

        guard let document = await self.context.resolveDocument(), !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult(
                "The exact active reader session is unavailable.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        let snapshot = document.snapshot
        let boundary = snapshot.readSoFarBoundary
        let boundaryCoordinator = AICurrentBookRetrievalBoundary(authorizationGate: authorizationGate)

        do {
            let rawHits = try await service.searchRaw(query: query, maxHits: 16)
            let bookHits = rawHits.filter { $0.bookFingerprintKey == snapshot.bookFingerprint.canonicalKey }

            var safeHits: [SemanticSearchHit] = []
            for hit in bookHits {
                let candidateChunk = AIDocumentChunk(
                    id: hit.chunkID,
                    bookFingerprintKey: hit.bookFingerprintKey,
                    sourceUnitID: hit.locator.href ?? "\(hit.pageIndex ?? 0)",
                    sourceUnitIndex: hit.pageIndex,
                    text: hit.snippet,
                    locator: hit.locator,
                    sourceLabel: hit.sourceLabel,
                    chapterTitle: hit.chapterTitle,
                    pageIndex: hit.pageIndex,
                    href: hit.href,
                    localStartUTF16: nil,
                    localEndUTF16: nil,
                    globalStartUTF16: nil,
                    globalEndUTF16: nil,
                    isOCRDerived: hit.isOCRDerived
                )
                if let _ = await boundaryCoordinator.authorizedText(
                    candidateChunk,
                    boundary: boundary,
                    toolName: Self.toolName,
                    actionDescription: "Semantic search in current book"
                ) {
                    safeHits.append(hit)
                    if safeHits.count >= 6 { break }
                }
            }

            let sources = safeHits.map { $0.toSourceProvenance(toolCallID: context.toolCallID) }
            await context.recordSources(sources)

            if safeHits.isEmpty {
                return AIReaderToolOutput.boundedResult(
                    "No semantically relevant passages found within the allowed reading range.",
                    maxBytes: maxContentBytes
                )
            }

            var outputLines: [String] = []
            for (idx, hit) in safeHits.enumerated() {
                let locDesc = hit.sourceLabel ?? "Match \(idx + 1)"
                outputLines.append("[\(locDesc)] \(hit.snippet)")
            }
            return AIReaderToolOutput.boundedResult(
                outputLines.joined(separator: "\n\n"),
                maxBytes: maxContentBytes
            )
        } catch {
            return AIReaderToolOutput.boundedResult(
                "Semantic search failed: \(error.localizedDescription)",
                maxBytes: maxContentBytes,
                isError: true
            )
        }
    }
}

struct SemanticSearchLibraryTool: AIContextualTool {
    static let toolName = "semantic_search_library"
    let service: SemanticSearchService
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        service: SemanticSearchService,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 8_000
    ) {
        self.service = service
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Search across the entire library using semantic meaning and concepts.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("The semantic concept or question to search across the library.")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        await run(input, context: AIToolExecutionContext())
    }

    func run(_ input: JSONValue, context: AIToolExecutionContext) async -> ToolResult {
        guard case .object(let dict) = input,
              case .string(let query)? = dict["query"],
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AIReaderToolOutput.boundedResult(
                "A non-empty query parameter is required.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            actionDescription: "Semantic search across library books",
            category: .readOtherBooks
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        do {
            let hits = try await service.searchRaw(query: query, maxHits: 8)
            let sources = hits.map { $0.toSourceProvenance(toolCallID: context.toolCallID) }
            await context.recordSources(sources)

            if hits.isEmpty {
                return AIReaderToolOutput.boundedResult(
                    "No semantically relevant results found across the library.",
                    maxBytes: maxContentBytes
                )
            }
            var outputLines: [String] = []
            for (idx, hit) in hits.enumerated() {
                let label = hit.sourceLabel ?? "Match \(idx + 1)"
                outputLines.append("[\(label)] \(hit.snippet)")
            }
            return AIReaderToolOutput.boundedResult(
                outputLines.joined(separator: "\n\n"),
                maxBytes: maxContentBytes
            )
        } catch {
            return AIReaderToolOutput.boundedResult(
                "Library semantic search failed: \(error.localizedDescription)",
                maxBytes: maxContentBytes,
                isError: true
            )
        }
    }
}

struct HybridSearchCurrentBookTool: AIContextualTool {
    static let toolName = "hybrid_search_current_book"
    let semanticService: SemanticSearchService
    let context: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        semanticService: SemanticSearchService,
        context: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 8_000
    ) {
        self.semanticService = semanticService
        self.context = context
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Search the current book using hybrid retrieval combining keyword search and semantic understanding.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("The search query or concept.")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        await run(input, context: AIToolExecutionContext())
    }

    func run(_ input: JSONValue, context: AIToolExecutionContext) async -> ToolResult {
        guard case .object(let dict) = input,
              case .string(let query)? = dict["query"],
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AIReaderToolOutput.boundedResult(
                "A non-empty query parameter is required.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        if let denied = await AICurrentReaderToolSupport.authorize(
            toolName: Self.toolName,
            action: "Hybrid search in the current book",
            context: self.context,
            gate: authorizationGate,
            maxBytes: maxContentBytes
        ) { return denied }

        guard let document = await self.context.resolveDocument(), !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult(
                "The exact active reader session is unavailable.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        let snapshot = document.snapshot
        let boundary = snapshot.readSoFarBoundary
        let boundaryCoordinator = AICurrentBookRetrievalBoundary(authorizationGate: authorizationGate)

        // 1. Semantic candidates with boundary validation
        var semanticHits: [SemanticSearchHit] = []
        if let rawSemantic = try? await semanticService.searchRaw(query: query, maxHits: 12) {
            let bookSemantic = rawSemantic.filter { $0.bookFingerprintKey == snapshot.bookFingerprint.canonicalKey }
            for hit in bookSemantic {
                let candidateChunk = AIDocumentChunk(
                    id: hit.chunkID,
                    bookFingerprintKey: hit.bookFingerprintKey,
                    sourceUnitID: hit.locator.href ?? "\(hit.pageIndex ?? 0)",
                    sourceUnitIndex: hit.pageIndex,
                    text: hit.snippet,
                    locator: hit.locator,
                    sourceLabel: hit.sourceLabel,
                    chapterTitle: hit.chapterTitle,
                    pageIndex: hit.pageIndex,
                    href: hit.href,
                    localStartUTF16: nil,
                    localEndUTF16: nil,
                    globalStartUTF16: nil,
                    globalEndUTF16: nil,
                    isOCRDerived: hit.isOCRDerived
                )
                if let _ = await boundaryCoordinator.authorizedText(
                    candidateChunk,
                    boundary: boundary,
                    toolName: Self.toolName,
                    actionDescription: "Hybrid search in current book"
                ) {
                    semanticHits.append(hit)
                }
            }
        }

        // 2. Fuse
        let fused = HybridSearchService.fuse(
            lexicalHits: [],
            semanticHits: semanticHits,
            maxResults: 8
        )

        let sources = fused.map { $0.toSourceProvenance(toolCallID: context.toolCallID) }
        await context.recordSources(sources)

        if fused.isEmpty {
            return AIReaderToolOutput.boundedResult(
                "No hybrid search results found in the current book.",
                maxBytes: maxContentBytes
            )
        }

        let lines = fused.enumerated().map { (idx, hit) in
            "[\(hit.sourceLabel ?? "Match \(idx + 1)")] \(hit.snippet)"
        }
        return AIReaderToolOutput.boundedResult(lines.joined(separator: "\n\n"), maxBytes: maxContentBytes)
    }
}

struct HybridSearchLibraryTool: AIContextualTool {
    static let toolName = "hybrid_search_library"
    let semanticService: SemanticSearchService
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        semanticService: SemanticSearchService,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 8_000
    ) {
        self.semanticService = semanticService
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Search across the entire library using hybrid retrieval combining keyword and semantic matching.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("The search query or concept.")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        await run(input, context: AIToolExecutionContext())
    }

    func run(_ input: JSONValue, context: AIToolExecutionContext) async -> ToolResult {
        guard case .object(let dict) = input,
              case .string(let query)? = dict["query"],
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AIReaderToolOutput.boundedResult(
                "A non-empty query parameter is required.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            actionDescription: "Hybrid search across library books",
            category: .readOtherBooks
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        let semanticHits = (try? await semanticService.searchRaw(query: query, maxHits: 12)) ?? []
        let fused = HybridSearchService.fuse(
            lexicalHits: [],
            semanticHits: semanticHits,
            maxResults: 8
        )

        let sources = fused.map { $0.toSourceProvenance(toolCallID: context.toolCallID) }
        await context.recordSources(sources)

        if fused.isEmpty {
            return AIReaderToolOutput.boundedResult(
                "No hybrid search results found across the library.",
                maxBytes: maxContentBytes
            )
        }

        let lines = fused.enumerated().map { (idx, hit) in
            "[\(hit.sourceLabel ?? "Match \(idx + 1)")] \(hit.snippet)"
        }
        return AIReaderToolOutput.boundedResult(lines.joined(separator: "\n\n"), maxBytes: maxContentBytes)
    }
}
