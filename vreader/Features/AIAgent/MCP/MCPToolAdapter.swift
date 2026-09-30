// Purpose: Dynamic tool adapter exposing remote MCP tools through VReader's AITool protocol.
// Enforces externalNetwork authorization, executes via MCPClientManager, and sanitizes output.

import Foundation

struct MCPToolAdapter: AITool {
    typealias Executor = @Sendable (String, JSONValue) async throws -> String

    let profileID: UUID
    let serverName: String
    let originalToolName: String
    let definition: ToolDefinition
    let clientManager: MCPClientManager
    let authorizationGate: AIAgentToolExecutionGate
    let sanitizer: MCPResultSanitizer
    let maxContentBytes: Int
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
            executor: executor
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        // Gated by externalNetwork permission category
        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: definition.name,
            actionDescription: "Call external tool \"\(originalToolName)\" on server \"\(serverName)\"",
            category: .externalNetwork,
            metadata: ["serverName": serverName, "originalToolName": originalToolName]
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        do {
            try Task.checkCancellation()
            let formatted: String
            if let executor = executor {
                let executed = try await executor(originalToolName, input)
                formatted = "[External Server: \(serverName)]\n" + executed
            } else {
                let rawResult = try await clientManager.invokeTool(
                    profileID: profileID,
                    toolName: originalToolName,
                    arguments: input
                )
                let sanitizedText = sanitizer.formatAsToolResult(rawResult)
                formatted = "[External Server: \(serverName)]\n" + sanitizedText
            }
            try Task.checkCancellation()
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
