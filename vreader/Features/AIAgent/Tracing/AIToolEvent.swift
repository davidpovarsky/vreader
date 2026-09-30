// Purpose: Lifecycle event models for tool execution observation.
// Captures state transitions: queued -> running -> awaitingConfirmation -> succeeded/failed/cancelled.

import Foundation

enum AIToolLifecycleState: String, Sendable, Codable, Equatable {
    case queued
    case running
    case awaitingConfirmation
    case succeeded
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: return true
        case .queued, .running, .awaitingConfirmation: return false
        }
    }
}

struct AIToolEvent: Sendable, Equatable, Codable, Identifiable {
    let id: UUID
    let toolCallID: String
    let toolName: String
    let phase: AIToolLifecycleState
    let timestamp: Date
    let argumentSummary: String?
    let resultSummary: String?
    let confirmationRequestID: UUID?
    let errorMessage: String?
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        toolCallID: String,
        toolName: String,
        phase: AIToolLifecycleState,
        timestamp: Date = Date(),
        argumentSummary: String? = nil,
        resultSummary: String? = nil,
        confirmationRequestID: UUID? = nil,
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.phase = phase
        self.timestamp = timestamp
        self.argumentSummary = argumentSummary
        self.resultSummary = resultSummary
        self.confirmationRequestID = confirmationRequestID
        self.errorMessage = errorMessage
        self.metadata = metadata
    }

    static func queued(callID: String, toolName: String, argumentSummary: String? = nil) -> AIToolEvent {
        AIToolEvent(toolCallID: callID, toolName: toolName, phase: .queued, argumentSummary: argumentSummary)
    }

    static func running(callID: String, toolName: String, argumentSummary: String? = nil) -> AIToolEvent {
        AIToolEvent(toolCallID: callID, toolName: toolName, phase: .running, argumentSummary: argumentSummary)
    }

    static func awaitingConfirmation(callID: String, toolName: String, requestID: UUID, description: String? = nil) -> AIToolEvent {
        AIToolEvent(toolCallID: callID, toolName: toolName, phase: .awaitingConfirmation, argumentSummary: description, confirmationRequestID: requestID)
    }

    static func succeeded(callID: String, toolName: String, resultSummary: String? = nil, metadata: [String: String] = [:]) -> AIToolEvent {
        AIToolEvent(toolCallID: callID, toolName: toolName, phase: .succeeded, resultSummary: resultSummary, metadata: metadata)
    }

    static func failed(callID: String, toolName: String, error: String? = nil, metadata: [String: String] = [:]) -> AIToolEvent {
        AIToolEvent(toolCallID: callID, toolName: toolName, phase: .failed, errorMessage: error, metadata: metadata)
    }

    static func cancelled(callID: String, toolName: String) -> AIToolEvent {
        AIToolEvent(toolCallID: callID, toolName: toolName, phase: .cancelled)
    }
}
