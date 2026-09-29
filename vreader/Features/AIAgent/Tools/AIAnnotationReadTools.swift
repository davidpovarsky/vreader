// Purpose: Bounded read/search tools over the existing annotation domain seams.

import Foundation

struct GetAnnotationsTool: AITool {
    static let toolName = "get_annotations"
    let store: any AIAnnotationReading
    let bookResolver: any BookContentProvider
    let readerContext: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxResults: Int
    let maxTextCharacters: Int
    let maxContentBytes: Int

    init(
        store: any AIAnnotationReading,
        bookResolver: any BookContentProvider,
        readerContext: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxResults: Int = 50,
        maxTextCharacters: Int = 500,
        maxContentBytes: Int = 12_000
    ) {
        self.store = store
        self.bookResolver = bookResolver
        self.readerContext = readerContext
        self.authorizationGate = authorizationGate
        self.maxResults = max(1, maxResults)
        self.maxTextCharacters = max(1, maxTextCharacters)
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Read bounded notes, highlights, and bookmarks for the current or named library book.",
            inputSchema: annotationSchema(requiresQuery: false)
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        await execute(input: input, query: nil)
    }

    fileprivate func execute(input: JSONValue, query: String?) async -> ToolResult {
        let target: AIAnnotationReadSupport.Target
        switch await AIAnnotationReadSupport.resolveTarget(
            input: input,
            bookResolver: bookResolver,
            readerContext: readerContext
        ) {
        case .success(let resolved):
            target = resolved
        case .failure(let message):
            return AIReaderToolOutput.boundedResult(
                message, maxBytes: maxContentBytes, isError: true
            )
        }

        let category: AIToolPermissionCategory = target.isCurrentBook
            ? .readCurrentBook
            : .readOtherBooks
        let outcome = await authorizationGate.authorize(
            AIAgentToolAuthorization.context(
                toolName: query == nil ? Self.toolName : SearchAnnotationsTool.toolName,
                actionDescription: query == nil
                    ? "Read annotations for \(target.title)"
                    : "Search annotations for \(target.title)",
                category: category,
                bookFingerprintKey: target.fingerprintKey
            )
        )
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(
                outcome, maxBytes: maxContentBytes
            )
        }
        guard !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult(
                "The annotation request was cancelled before it could run.",
                maxBytes: maxContentBytes, isError: true
            )
        }

        let collection: AIAnnotationCollection
        do {
            collection = try await store.readAnnotations(
                fingerprintKey: target.fingerprintKey
            )
        } catch {
            return AIReaderToolOutput.boundedResult(
                "Annotations could not be read for that book.",
                maxBytes: maxContentBytes, isError: true
            )
        }
        guard !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult(
                "The annotation request was cancelled before results could be returned.",
                maxBytes: maxContentBytes, isError: true
            )
        }
        var items = AIAnnotationReadSupport.items(collection)
        if let query {
            items = items.filter {
                $0.text.localizedCaseInsensitiveContains(query)
            }
        }
        if target.isCurrentBook {
            guard let safe = await AIAnnotationReadSupport.authorizedCurrentItems(
                items,
                context: readerContext,
                authorizationGate: authorizationGate,
                toolName: query == nil ? Self.toolName : SearchAnnotationsTool.toolName
            ) else {
                return AIReaderToolOutput.boundedResult(
                    "The exact active reader session is unavailable.",
                    maxBytes: maxContentBytes, isError: true
                )
            }
            items = safe
        }
        let total = items.count
        return AIReaderToolOutput.boundedResult(
            AIAnnotationReadSupport.formatted(
                Array(items.prefix(maxResults)),
                total: total,
                title: target.title,
                maxTextCharacters: maxTextCharacters,
                maxBytes: maxContentBytes
            ),
            maxBytes: maxContentBytes
        )
    }

    fileprivate func annotationSchema(requiresQuery: Bool) -> JSONValue {
        var properties: [String: JSONValue] = [
            "book_title": .object([
                "type": .string("string"),
                "description": .string("Optional exact library title; omit for the current book."),
            ]),
        ]
        if requiresQuery {
            properties["query"] = .object([
                "type": .string("string"),
                "description": .string("Non-empty text to find in annotation content."),
            ])
        }
        var schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        if requiresQuery { schema["required"] = .array([.string("query")]) }
        return .object(schema)
    }
}

struct SearchAnnotationsTool: AITool {
    static let toolName = "search_annotations"
    private let base: GetAnnotationsTool

    init(
        store: any AIAnnotationReading,
        bookResolver: any BookContentProvider,
        readerContext: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxResults: Int = 30,
        maxTextCharacters: Int = 500,
        maxContentBytes: Int = 12_000
    ) {
        base = GetAnnotationsTool(
            store: store,
            bookResolver: bookResolver,
            readerContext: readerContext,
            authorizationGate: authorizationGate,
            maxResults: maxResults,
            maxTextCharacters: maxTextCharacters,
            maxContentBytes: maxContentBytes
        )
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Search bounded annotation text in the current or named library book.",
            inputSchema: base.annotationSchema(requiresQuery: true)
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        guard let query = input["query"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty,
              query.count <= 256 else {
            return AIReaderToolOutput.boundedResult(
                "Missing or invalid query; provide 1 to 256 characters.",
                maxBytes: base.maxContentBytes, isError: true
            )
        }
        return await base.execute(input: input, query: query)
    }
}
