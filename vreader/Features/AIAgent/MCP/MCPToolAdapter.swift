// Purpose: Dynamic tool adapter exposing remote MCP tools through VReader's AITool protocol.
// Enforces externalNetwork authorization, executes via MCPClientManager, and sanitizes output.

import Foundation

struct MCPToolAdapter: AITool {
    let profileID: UUID
    let serverName: String
    let originalToolName: String
    let definition: ToolDefinition
    let clientManager: MCPClientManager
    let authorizationGate: AIAgentToolExecutionGate
    let sanitizer: MCPResultSanitizer
    let maxContentBytes: Int

    init(
        profileID: UUID,
        serverName: String,
        originalToolName: String,
        definition: ToolDefinition,
        clientManager: MCPClientManager = MCPClientManager.shared,
        authorizationGate: AIAgentToolExecutionGate,
        sanitizer: MCPResultSanitizer = MCPResultSanitizer(),
        maxContentBytes: Int = 8_000
    ) {
        self.profileID = profileID
        self.serverName = serverName
        self.originalToolName = originalToolName
        self.definition = definition
        self.clientManager = clientManager
        self.authorizationGate = authorizationGate
        self.sanitizer = sanitizer
        self.maxContentBytes = max(256, maxContentBytes)
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
            let rawResult = try await clientManager.invokeTool(
                profileID: profileID,
                toolName: originalToolName,
                arguments: input
            )
            try Task.checkCancellation()

            let sanitizedText = sanitizer.formatAsToolResult(rawResult)
            let formatted = "[External Server: \(serverName)]\n" + sanitizedText
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
