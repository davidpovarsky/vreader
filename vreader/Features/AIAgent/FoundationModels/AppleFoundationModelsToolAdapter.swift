// Purpose: Adapts VReader domain tools into Apple Foundation Models native tool calls.
// Shares the exact same authorization, boundary policy, idempotency, and provenance infrastructure.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

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

    /// Executes a tool call parsed from Apple Foundation Models output with full execution context.
    func invoke(
        toolName: String,
        input: JSONValue,
        callID: String = UUID().uuidString,
        turnID: String = UUID().uuidString,
        documentSessionID: AIDocumentSessionID? = nil,
        eventSink explicitSink: (any AIToolEventSink)? = nil
    ) async -> ToolResult {
        let sink = explicitSink ?? self.eventSink
        let summary: String
        if case .object(let dict) = input {
            summary = dict.keys.joined(separator: ", ")
        } else {
            summary = ""
        }
        await sink.emit(AIToolEvent(
            toolCallID: callID,
            toolName: toolName,
            phase: .running,
            argumentSummary: summary
        ))

        let toolCall = ToolCall(id: callID, name: toolName, input: input)

        guard registry.hasTool(named: toolName) else {
            let notFound = ToolResult(toolUseID: callID, content: "Tool not found: \(toolName)", isError: true)
            await sink.emit(AIToolEvent(
                toolCallID: callID,
                toolName: toolName,
                phase: .failed,
                errorMessage: "Tool not found"
            ))
            return notFound
        }

        let execContext = AIToolExecutionContext(
            toolCallID: callID,
            turnID: turnID,
            eventSink: sink,
            readerSessionID: documentSessionID
        )

        let result = await registry.run(toolCall, context: execContext)

        if result.isError {
            await sink.emit(AIToolEvent(
                toolCallID: callID,
                toolName: toolName,
                phase: .failed,
                errorMessage: result.content
            ))
        } else {
            await sink.emit(AIToolEvent(
                toolCallID: callID,
                toolName: toolName,
                phase: .succeeded,
                resultSummary: AIToolDisplayMetadata.safeResultSummary(result.content, isError: false)
            ))
        }

        return result
    }

    /// Convenience overload accepting Foundation dictionary arguments.
    func invoke(
        toolName: String,
        arguments: [String: Any],
        callID: String = UUID().uuidString,
        turnID: String = UUID().uuidString,
        documentSessionID: AIDocumentSessionID? = nil
    ) async -> ToolResult {
        await invoke(
            toolName: toolName,
            input: JSONValue(foundation: arguments),
            callID: callID,
            turnID: turnID,
            documentSessionID: documentSessionID
        )
    }

    /// Invokes a native tool call with raw arguments and commit/discard provenance tracking.
    func invokeNative(
        toolName: String,
        rawArguments: String,
        callID: String = UUID().uuidString,
        turnID: String = UUID().uuidString,
        documentSessionID: AIDocumentSessionID? = nil,
        sink: ProvenanceTapSink? = nil
    ) async -> ToolResult {
        let jsonValue: JSONValue
        if let data = rawArguments.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            jsonValue = JSONValue(foundation: jsonObject)
        } else if rawArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            jsonValue = .object([:])
        } else {
            jsonValue = .string(rawArguments)
        }

        let result = await invoke(
            toolName: toolName,
            input: jsonValue,
            callID: callID,
            turnID: turnID,
            documentSessionID: documentSessionID,
            eventSink: sink
        )

        if result.isError {
            await sink?.discardSources(for: callID)
        } else {
            await sink?.commitSources(for: callID)
        }

        return result
    }

    var definitions: [ToolDefinition] {
        registry.definitions()
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

    init(
        tools: [any AITool],
        executionGate: AIAgentToolExecutionGate = .productionUnavailable(),
        eventSink: any AIToolEventSink = NoOpAIToolEventSink.shared
    ) {
        self.registry = AIToolRegistry(tools)
        self.executionGate = executionGate
        self.eventSink = eventSink
    }

    /// Executes the first registered tool using raw JSON string arguments.
    func execute(argumentsJSON: String, callID: String = UUID().uuidString) async -> String {
        guard let toolName = registry.definitions().first?.name else {
            return "No tool registered"
        }
        return await executeToolCall(name: toolName, arguments: argumentsJSON, callID: callID)
    }

    /// Executes a registered tool by name with a JSON arguments string.
    func executeToolCall(name: String, arguments: String, callID: String = UUID().uuidString) async -> String {
        guard let data = arguments.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Invalid JSON arguments"
        }
        let result = await invoke(toolName: name, input: JSONValue(foundation: jsonObject), callID: callID)
        return result.content
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
struct AppleNativeToolBridge: Tool, Sendable {
    @Generable
    struct Arguments: Sendable {
        @Guide(description: "Input arguments or JSON string for the tool")
        var input: String = ""
    }

    typealias Output = String

    let name: String
    let description: String
    let adapter: AppleFoundationModelsToolAdapter
    let turnID: String
    let documentSessionID: AIDocumentSessionID?
    let sink: ProvenanceTapSink

    init(
        name: String,
        description: String,
        adapter: AppleFoundationModelsToolAdapter,
        turnID: String,
        documentSessionID: AIDocumentSessionID?,
        sink: ProvenanceTapSink
    ) {
        self.name = name
        self.description = description
        self.adapter = adapter
        self.turnID = turnID
        self.documentSessionID = documentSessionID
        self.sink = sink
    }

    func call(arguments: Arguments) async throws -> String {
        let callID = UUID().uuidString
        let result = await adapter.invokeNative(
            toolName: name,
            rawArguments: arguments.input,
            callID: callID,
            turnID: turnID,
            documentSessionID: documentSessionID,
            sink: sink
        )
        return result.content
    }
}

extension AppleFoundationModelsToolAdapter {
    @available(iOS 26.0, macOS 26.0, *)
    func makeNativeTools(
        turnID: String,
        documentSessionID: AIDocumentSessionID?,
        sink: ProvenanceTapSink
    ) -> [any Tool] {
        registry.definitions().map { def in
            AppleNativeToolBridge(
                name: def.name,
                description: def.description,
                adapter: self,
                turnID: turnID,
                documentSessionID: documentSessionID,
                sink: sink
            )
        }
    }
}
#endif
