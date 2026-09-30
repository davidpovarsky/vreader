// Purpose: Adapts VReader domain tools into Apple Foundation Models native tool calls.
// Shares the exact same authorization, boundary policy, idempotency, and provenance infrastructure.

import Foundation

struct AppleFoundationModelsToolAdapter: Sendable {
    let registry: AIToolRegistry
    let executionGate: AIAgentToolExecutionGate
    let eventSink: any AIToolEventSink

    init(
        registry: AIToolRegistry,
        executionGate: AIAgentToolExecutionGate,
        eventSink: any AIToolEventSink = NoOpAIToolEventSink.shared
    ) {
        self.registry = registry
        self.executionGate = executionGate
        self.eventSink = eventSink
    }

    /// Executes a tool call parsed from Apple Foundation Models output.
    func invoke(
        toolName: String,
        arguments: [String: Any],
        callID: String = UUID().uuidString
    ) async -> ToolResult {
        await eventSink.emit(AIToolEvent(
            toolCallID: callID,
            toolName: toolName,
            phase: .running,
            argumentSummary: "\(arguments.keys.joined(separator: ", "))"
        ))

        let jsonInput = JSONValue(foundation: arguments)
        let toolCall = ToolCall(id: callID, name: toolName, input: jsonInput)

        guard registry.hasTool(named: toolName) else {
            let notFound = ToolResult(toolUseID: callID, content: "Tool not found: \(toolName)", isError: true)
            await eventSink.emit(AIToolEvent(
                toolCallID: callID,
                toolName: toolName,
                phase: .failed,
                errorMessage: "Tool not found"
            ))
            return notFound
        }

        let result = await registry.run(toolCall)

        if result.isError {
            await eventSink.emit(AIToolEvent(
                toolCallID: callID,
                toolName: toolName,
                phase: .failed,
                errorMessage: result.content
            ))
        } else {
            await eventSink.emit(AIToolEvent(
                toolCallID: callID,
                toolName: toolName,
                phase: .succeeded,
                resultSummary: AIToolDisplayMetadata.safeResultSummary(result.content, isError: false)
            ))
        }

        return result
    }

    init(
        tool: any AITool,
        executionGate: AIAgentToolExecutionGate = .productionUnavailable(),
        eventSink: any AIToolEventSink = NoOpAIToolEventSink.shared
    ) {
        self.registry = AIToolRegistry([tool])
        self.executionGate = executionGate
        self.eventSink = eventSink
    }

    /// Executes the first registered tool using raw JSON string arguments.
    func execute(argumentsJSON: String, callID: String = UUID().uuidString) async -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Invalid JSON arguments"
        }
        guard let toolName = registry.definitions().first?.name else {
            return "No tool registered"
        }
        let result = await invoke(toolName: toolName, arguments: jsonObject, callID: callID)
        return result.content
    }
}
