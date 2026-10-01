// Purpose: Dynamic tool adapter exposing remote MCP tools through VReader's AIContextualTool protocol.
// Enforces externalNetwork authorization, executes via MCPClientManager, sanitizes output, and emits source provenance.

import Foundation

struct MCPToolAdapter: AIContextualTool {
    typealias Executor = @Sendable (String, JSONValue) async throws -> String

    let profileID: UUID
    let serverName: String
    let originalToolName: String
    let definition: ToolDefinition
    let clientManager: MCPClientManager
    let authorizationGate: AIAgentToolExecutionGate
    let sanitizer: MCPResultSanitizer
    let maxContentBytes: Int
    let readerSessionID: AIDocumentSessionID?
    let executor: Executor?

    init(
        profileID: UUID = UUID(),
        serverName: String,
        originalToolName: String,
        definition: ToolDefinition,
        clientManager: MCPClientManager = MCPClientManager.shared,
        authorizationGate: AIAgentToolExecutionGate,
        sanitizer: MCPResultSanitizer = MCPResultSanitizer(),
        maxContentBytes: Int = 8_000,
        readerSessionID: AIDocumentSessionID? = nil,
        executor: Executor? = nil
    ) {
        self.profileID = profileID
        self.serverName = serverName
        self.originalToolName = originalToolName
        self.definition = definition
        self.clientManager = clientManager
        self.authorizationGate = authorizationGate
        self.sanitizer = sanitizer
        self.maxContentBytes = max(256, maxContentBytes)
        self.readerSessionID = readerSessionID
        self.executor = executor
    }

    init(
        definition: ToolDefinition,
        serverName: String,
        originalToolName: String,
        profileID: UUID = UUID(),
        clientManager: MCPClientManager = MCPClientManager.shared,
        authorizationGate: AIAgentToolExecutionGate,
        sanitizer: MCPResultSanitizer = MCPResultSanitizer(),
        maxContentBytes: Int = 8_000,
        readerSessionID: AIDocumentSessionID? = nil,
        executor: Executor? = nil
    ) {
        self.init(
            profileID: profileID,
            serverName: serverName,
            originalToolName: originalToolName,
            definition: definition,
            clientManager: clientManager,
            authorizationGate: authorizationGate,
            sanitizer: sanitizer,
            maxContentBytes: maxContentBytes,
            readerSessionID: readerSessionID,
            executor: executor
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        await run(input, context: .fallback(toolCallID: UUID().uuidString))
    }

    func run(_ input: JSONValue, context: AIToolExecutionContext) async -> ToolResult {
        let effectiveSessionID = context.readerSessionID ?? readerSessionID
        // Gated by externalNetwork permission category with session identity
        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: definition.name,
            actionDescription: "Call external tool \"\(originalToolName)\" on server \"\(serverName)\"",
            category: .externalNetwork,
            readerSessionID: effectiveSessionID,
            metadata: ["serverName": serverName, "originalToolName": originalToolName]
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        do {
            try Task.checkCancellation()
            let formatted: String
            let outputSnippet: String
            if let executor = executor {
                let executed = try await executor(originalToolName, input)
                outputSnippet = executed
                formatted = "[External Server: \(serverName)]\n" + executed
            } else {
                let rawResult = try await clientManager.invokeTool(
                    profileID: profileID,
                    toolName: originalToolName,
                    arguments: input
                )
                let sanitizedText = sanitizer.formatAsToolResult(rawResult)
                outputSnippet = sanitizedText
                formatted = "[External Server: \(serverName)]\n" + sanitizedText
            }
            try Task.checkCancellation()

            let provenance = AISourceProvenance(
                bookFingerprintKey: "mcp:\(profileID.uuidString)",
                sourceLabel: "\(serverName): \(originalToolName)",
                snippet: outputSnippet,
                retrievalMethod: .mcpExternal,
                toolCallID: context.toolCallID,
                mcpServerName: serverName
            )
            await context.recordSources([provenance])

            return AIReaderToolOutput.boundedResult(formatted, maxBytes: maxContentBytes)
        } catch is CancellationError {
            return AIReaderToolOutput.boundedResult(
                "MCP call cancelled.",
                maxBytes: maxContentBytes,
                isError: true
            )
        } catch {
            return AIReaderToolOutput.boundedResult(
                "MCP server call failed: \(error.localizedDescription)",
                maxBytes: maxContentBytes,
                isError: true
            )
        }
    }
}
