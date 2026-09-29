// Purpose: Read-only exact-session reader tools for Feature #177 WI-6.

import Foundation

private struct AICurrentLocationPayload: Encodable {
    let title: String
    let format: String
    let sourceLabel: String?
    let chapterLabel: String?
    let page: Int?
    let href: String?
    let progress: Double?
    let locatorJSON: String
}

struct GetCurrentLocationTool: AITool {
    static let toolName = "get_current_location"
    let context: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        context: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 4_000
    ) {
        self.context = context
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Report the exact active reader location without reading body text.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        if let denied = await AICurrentReaderToolSupport.authorize(
            toolName: Self.toolName,
            action: "Read the current reader location",
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
        let locator = snapshot.currentLocator ?? snapshot.readSoFarBoundary.locator
        do {
            let payload = AICurrentLocationPayload(
                title: await context.bookTitle,
                format: snapshot.format.rawValue,
                sourceLabel: snapshot.currentSectionChunks.first?.sourceLabel,
                chapterLabel: snapshot.currentChapterLabel,
                page: locator.page.map { $0 + 1 },
                href: locator.href,
                progress: locator.totalProgression,
                locatorJSON: try AIReaderToolOutput.encode(locator)
            )
            return AIReaderToolOutput.boundedResult(
                try AIReaderToolOutput.encode(payload), maxBytes: maxContentBytes
            )
        } catch {
            return AIReaderToolOutput.boundedResult(
                "The current location could not be encoded.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }
    }
}

struct GetCurrentContextTool: AITool {
    static let toolName = "get_current_context"
    let context: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        context: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 8_000
    ) {
        self.context = context
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Read the bounded structured section at the exact active location.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        await runStructuredContext(
            scope: .section,
            budget: AIContextBudget.sectionMaxUTF16,
            toolName: Self.toolName,
            action: "Read the current structured context"
        )
    }

    private func runStructuredContext(
        scope: AIDocumentContextScope,
        budget: Int,
        toolName: String,
        action: String
    ) async -> ToolResult {
        if let denied = await AICurrentReaderToolSupport.authorize(
            toolName: toolName, action: action, context: context,
            gate: authorizationGate, maxBytes: maxContentBytes
        ) { return denied }
        guard let document = await context.resolveDocument(), !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult(
                "The exact active reader session is unavailable.",
                maxBytes: maxContentBytes, isError: true
            )
        }
        guard let resolved = await AICurrentReaderToolSupport.safeContext(
            document: document,
            scope: scope,
            boundaryCoordinator: AICurrentBookRetrievalBoundary(
                authorizationGate: authorizationGate
            ),
            toolName: toolName,
            budget: budget
        ), !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult(
                "No text at this location is authorized within the current reading boundary.",
                maxBytes: maxContentBytes, isError: true
            )
        }
        return AIReaderToolOutput.boundedResult(
            "Structured current context:\n" + resolved.text,
            maxBytes: maxContentBytes
        )
    }
}

struct GetCurrentChapterTool: AITool {
    static let toolName = "get_current_chapter"
    let context: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        context: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 24_000
    ) {
        self.context = context
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Read the bounded current chapter-equivalent from the live reader.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        if let denied = await AICurrentReaderToolSupport.authorize(
            toolName: Self.toolName,
            action: "Read the current chapter",
            context: context,
            gate: authorizationGate,
            maxBytes: maxContentBytes
        ) { return denied }
        guard let document = await context.resolveDocument(), !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult(
                "The exact active reader session is unavailable.",
                maxBytes: maxContentBytes, isError: true
            )
        }
        let budget: Int
        switch document.snapshot.format {
        case .pdf, .azw3:
            budget = AIContextBudget.sectionMaxUTF16
        case .txt, .md, .epub:
            budget = AIContextBudget.defaultMaxUTF16
        }
        guard let resolved = await AICurrentReaderToolSupport.safeContext(
            document: document,
            scope: .chapter,
            boundaryCoordinator: AICurrentBookRetrievalBoundary(
                authorizationGate: authorizationGate
            ),
            toolName: Self.toolName,
            budget: budget
        ), !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult(
                "No chapter text is authorized within the current reading boundary.",
                maxBytes: maxContentBytes, isError: true
            )
        }
        return AIReaderToolOutput.boundedResult(
            "Structured current chapter:\n" + resolved.text,
            maxBytes: maxContentBytes
        )
    }
}

struct GetTableOfContentsTool: AITool {
    static let toolName = "get_table_of_contents"
    let context: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxEntries: Int
    let maxContentBytes: Int

    init(
        context: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxEntries: Int = 100,
        maxContentBytes: Int = 12_000
    ) {
        self.context = context
        self.authorizationGate = authorizationGate
        self.maxEntries = max(1, maxEntries)
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "List a bounded table of contents with exact navigation targets.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        if let denied = await AICurrentReaderToolSupport.authorize(
            toolName: Self.toolName,
            action: "Read the current book table of contents",
            context: context,
            gate: authorizationGate,
            maxBytes: maxContentBytes
        ) { return denied }
        let entries = await context.tableOfContents()
        guard !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult(
                "The action was cancelled before it could run.",
                maxBytes: maxContentBytes, isError: true
            )
        }
        guard !entries.isEmpty else {
            return AIReaderToolOutput.boundedResult(
                "This book has no structured table of contents.",
                maxBytes: maxContentBytes
            )
        }
        let shown = Array(entries.prefix(maxEntries))
        var lines = [shown.count < entries.count
            ? "Showing \(shown.count) of \(entries.count) table-of-contents entries:"
            : "\(entries.count) table-of-contents entries:"]
        for entry in shown {
            let locator = (try? AIReaderToolOutput.encode(entry.locator)) ?? "{}"
            lines.append("- depth=\(entry.depth) title=\(ToolResultText.oneLine(entry.title, maxChars: 160)) locator_json=\(locator)")
        }
        return AIReaderToolOutput.boundedResult(
            lines.joined(separator: "\n"), maxBytes: maxContentBytes
        )
    }
}
