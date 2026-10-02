// Purpose: Semantic search tools querying the vector ANN index.
// Enforces strict spoiler boundary rules and preserves exact UTF-16 ranges and locators.

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
            description: "Search the current book using semantic concept similarity rather than exact keywords. Returns relevant passages within the allowed reading range.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("The semantic concept or meaning to find in the book.")
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
            action: "Semantic search in current book: \"\(query.prefix(30))...\"",
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
                    sourceUnitID: hit.sourceUnitID ?? hit.locator.href ?? "\(hit.pageIndex ?? 0)",
                    sourceUnitIndex: hit.sourceUnitIndex ?? hit.pageIndex,
                    text: hit.snippet,
                    locator: hit.locator,
                    sourceLabel: hit.sourceLabel,
                    chapterTitle: hit.chapterTitle,
                    pageIndex: hit.pageIndex,
                    href: hit.href,
                    localStartUTF16: hit.localStartUTF16,
                    localEndUTF16: hit.localEndUTF16,
                    globalStartUTF16: hit.globalStartUTF16,
                    globalEndUTF16: hit.globalEndUTF16,
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

            let lines = safeHits.enumerated().map { (idx, hit) in
                "[\(hit.sourceLabel ?? "Result \(idx + 1)")] \(hit.snippet)"
            }
            return AIReaderToolOutput.boundedResult(lines.joined(separator: "\n\n"), maxBytes: maxContentBytes)
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
            description: "Search across all books in the library using semantic concept similarity rather than exact keywords.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("The semantic concept or meaning to search for across the library.")
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
            let hits = try await service.searchLibrary(query: query, maxHits: 8)
            let sources = hits.map { $0.toSourceProvenance(toolCallID: context.toolCallID) }
            await context.recordSources(sources)

            if hits.isEmpty {
                return AIReaderToolOutput.boundedResult(
                    "No semantically relevant passages found across the library.",
                    maxBytes: maxContentBytes
                )
            }

            let lines = hits.enumerated().map { (idx, hit) in
                "[\(hit.bookTitle ?? "Book"): \(hit.sourceLabel ?? "Result \(idx + 1)")] \(hit.snippet)"
            }
            return AIReaderToolOutput.boundedResult(lines.joined(separator: "\n\n"), maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult(
                "Library semantic search failed: \(error.localizedDescription)",
                maxBytes: maxContentBytes,
                isError: true
            )
        }
    }
}
