// Purpose: Model-facing tools for current-book and library semantic search.
// Fully gated by AIAgentToolExecutionGate and spoiler-safe against the active reader boundary.

import Foundation

struct SemanticSearchCurrentBookTool: AITool {
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
            context: context,
            gate: authorizationGate,
            maxBytes: maxContentBytes
        ) { return denied }

        guard let document = await context.resolveDocument(), !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult(
                "The exact active reader session is unavailable.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        let snapshot = document.snapshot
        let boundary = snapshot.readSoFarBoundary

        // Check if read ahead is allowed
        let readAheadOutcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Read ahead via semantic search",
            category: .readAhead
        ))
        let readAheadAllowed = (readAheadOutcome == .allowed)

        do {
            let hits = try await service.searchCurrentBook(
                query: query,
                bookFingerprintKey: snapshot.bookFingerprint.canonicalKey,
                boundary: boundary,
                readAheadAllowed: readAheadAllowed,
                maxHits: 6
            )

            if hits.isEmpty {
                return AIReaderToolOutput.boundedResult(
                    "No semantically relevant passages found within the allowed reading range.",
                    maxBytes: maxContentBytes
                )
            }

            var outputLines: [String] = []
            for (idx, hit) in hits.enumerated() {
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

struct SemanticSearchLibraryTool: AITool {
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
            action: "Semantic search across library books",
            category: .readOtherBooks
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        do {
            let hits = try await service.searchRaw(query: query, maxHits: 8)
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
