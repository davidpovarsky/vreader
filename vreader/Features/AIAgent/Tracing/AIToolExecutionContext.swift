// Purpose: Context passed to tool execution containing call IDs, session tokens, and event sinks.

import Foundation

struct AIToolExecutionContext: Sendable {
    let toolCallID: String
    let turnID: String
    let eventSink: any AIToolEventSink
    let readerSessionID: AIDocumentSessionID?

    init(
        toolCallID: String = UUID().uuidString,
        turnID: String = UUID().uuidString,
        eventSink: any AIToolEventSink = NoOpAIToolEventSink.shared,
        readerSessionID: AIDocumentSessionID? = nil
    ) {
        self.toolCallID = toolCallID
        self.turnID = turnID
        self.eventSink = eventSink
        self.readerSessionID = readerSessionID
    }

    func emitQueued(toolName: String, argumentSummary: String? = nil) async {
        await eventSink.emit(AIToolEvent(
            toolCallID: toolCallID,
            toolName: toolName,
            phase: .queued,
            argumentSummary: argumentSummary
        ))
    }

    func emitRunning(toolName: String, argumentSummary: String? = nil) async {
        await eventSink.emit(AIToolEvent(
            toolCallID: toolCallID,
            toolName: toolName,
            phase: .running,
            argumentSummary: argumentSummary
        ))
    }

    func emitAwaitingConfirmation(toolName: String, requestID: UUID, description: String) async {
        await eventSink.emit(AIToolEvent(
            toolCallID: toolCallID,
            toolName: toolName,
            phase: .awaitingConfirmation,
            argumentSummary: description,
            confirmationRequestID: requestID
        ))
    }

    func emitSucceeded(toolName: String, resultSummary: String? = nil, metadata: [String: String] = [:]) async {
        await eventSink.emit(AIToolEvent(
            toolCallID: toolCallID,
            toolName: toolName,
            phase: .succeeded,
            resultSummary: resultSummary,
            metadata: metadata
        ))
    }

    func emitFailed(toolName: String, error: String, metadata: [String: String] = [:]) async {
        await eventSink.emit(AIToolEvent(
            toolCallID: toolCallID,
            toolName: toolName,
            phase: .failed,
            errorMessage: error,
            metadata: metadata
        ))
    }

    func emitCancelled(toolName: String, reason: String? = "Cancelled") async {
        await eventSink.emit(AIToolEvent(
            toolCallID: toolCallID,
            toolName: toolName,
            phase: .cancelled,
            resultSummary: reason
        ))
    }
}
