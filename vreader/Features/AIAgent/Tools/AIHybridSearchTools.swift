// Purpose: Hybrid search tools combining lexical FTS5 and semantic ANN results.
// Implements real reciprocal rank fusion with canonical deduplication and spoiler boundaries.

import Foundation

struct HybridSearchCurrentBookTool: AIContextualTool {
    static let toolName = "hybrid_search_current_book"
    let semanticService: SemanticSearchService
    let lexicalSearch: (any SearchProviding)?
    let context: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        semanticService: SemanticSearchService,
        lexicalSearch: (any SearchProviding)? = nil,
        context: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 8_000
    ) {
        self.semanticService = semanticService
        self.lexicalSearch = lexicalSearch
        self.context = context
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Search the current book using hybrid retrieval combining exact keyword matches and semantic concepts.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("The search query or concept to find in the book.")
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
            action: "Hybrid search in current book: \"\(query.prefix(30))...\"",
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

        // 1. Semantic candidates
        var semanticHits: [SemanticSearchHit] = []
        if let rawSemantic = try? await semanticService.searchRaw(query: query, maxHits: 12) {
            semanticHits = rawSemantic.filter { $0.bookFingerprintKey == snapshot.bookFingerprint.canonicalKey }
        }

        // 2. Lexical candidates from real FTS5 backend
        var lexicalSnippets: [SearchSnippet] = []
        if let lexicalSearch {
            if let lexPage = try? await lexicalSearch.search(
                query: query,
                bookFingerprint: snapshot.bookFingerprint,
                page: 0,
                pageSize: 12
            ) {
                let currentTitle = await self.context.bookTitle
                lexicalSnippets = lexPage.results.map { res in
                    SearchSnippet(
                        bookFingerprintKey: snapshot.bookFingerprint.canonicalKey,
                        bookTitle: currentTitle,
                        locator: res.locator,
                        sourceLabel: res.locator.href ?? res.locator.page.map { "Page \($0 + 1)" } ?? "Lexical match",
                        chapterTitle: nil,
                        pageIndex: res.locator.page,
                        href: res.locator.href,
                        snippet: ToolResultText.oneLine(res.snippet, maxChars: 300),
                        aheadOfReader: false
                    )
                }
            }
        }

        // 3. Reciprocal Rank Fusion
        let fused = HybridSearchService.fuse(
            lexicalHits: lexicalSnippets,
            semanticHits: semanticHits,
            maxResults: 12
        )

        // 4. Boundary spoiler filtering on fused candidates
        var safeHits: [HybridSearchHit] = []
        for hit in fused {
            let candidateChunk = AIDocumentChunk(
                id: hit.id,
                bookFingerprintKey: hit.bookFingerprintKey,
                sourceUnitID: hit.locator.href ?? "\(hit.pageIndex ?? 0)",
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
                actionDescription: "Hybrid search in current book"
            ) {
                safeHits.append(hit)
                if safeHits.count >= 8 { break }
            }
        }

        let sources = safeHits.map { $0.toSourceProvenance(toolCallID: context.toolCallID) }
        await context.recordSources(sources)

        if safeHits.isEmpty {
            return AIReaderToolOutput.boundedResult(
                "No hybrid search results found within the allowed reading range.",
                maxBytes: maxContentBytes
            )
        }

        let lines = safeHits.enumerated().map { (idx, hit) in
            "[\(hit.sourceLabel ?? "Match \(idx + 1)")] \(hit.snippet)"
        }
        return AIReaderToolOutput.boundedResult(lines.joined(separator: "\n\n"), maxBytes: maxContentBytes)
    }
}

struct HybridSearchLibraryTool: AIContextualTool {
    static let toolName = "hybrid_search_library"
    let semanticService: SemanticSearchService
    let libraryBackend: (any LibrarySearchBackend)?
    let currentBookFingerprintKey: String?
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        semanticService: SemanticSearchService,
        libraryBackend: (any LibrarySearchBackend)? = nil,
        currentBookFingerprintKey: String? = nil,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 8_000
    ) {
        self.semanticService = semanticService
        self.libraryBackend = libraryBackend
        self.currentBookFingerprintKey = currentBookFingerprintKey
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

        // 1. Semantic candidates
        let semanticHits = (try? await semanticService.searchRaw(query: query, maxHits: 12)) ?? []

        // 2. Lexical candidates from real library search backend
        var lexicalSnippets: [SearchSnippet] = []
        if let libraryBackend, let books = try? await libraryBackend.libraryBooks() {
            let others = books.filter { $0.fingerprintKey != currentBookFingerprintKey }
            for book in others.prefix(6) {
                guard let fp = DocumentFingerprint(canonicalKey: book.fingerprintKey) else { continue }
                if let page = try? await libraryBackend.search(query: query, fingerprint: fp, limit: 3) {
                    for res in page.results {
                        lexicalSnippets.append(SearchSnippet(
                            bookFingerprintKey: book.fingerprintKey,
                            bookTitle: book.title,
                            locator: res.locator,
                            sourceLabel: book.title,
                            chapterTitle: nil,
                            pageIndex: res.locator.page,
                            href: res.locator.href,
                            snippet: ToolResultText.oneLine(res.snippet, maxChars: 300),
                            aheadOfReader: false
                        ))
                    }
                }
            }
        }

        // 3. Reciprocal Rank Fusion
        let fused = HybridSearchService.fuse(
            lexicalHits: lexicalSnippets,
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
