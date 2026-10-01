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
    let sources: [AISourceProvenance]

    enum CodingKeys: String, CodingKey {
        case id
        case toolCallID
        case toolName
        case phase
        case timestamp
        case argumentSummary
        case resultSummary
        case confirmationRequestID
        case errorMessage
        case metadata
        case sources
    }

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
        metadata: [String: String] = [:],
        sources: [AISourceProvenance] = []
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
        self.sources = sources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.toolCallID = try container.decode(String.self, forKey: .toolCallID)
        self.toolName = try container.decode(String.self, forKey: .toolName)
        self.phase = try container.decode(AIToolLifecycleState.self, forKey: .phase)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.argumentSummary = try container.decodeIfPresent(String.self, forKey: .argumentSummary)
        self.resultSummary = try container.decodeIfPresent(String.self, forKey: .resultSummary)
        self.confirmationRequestID = try container.decodeIfPresent(UUID.self, forKey: .confirmationRequestID)
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        self.sources = try container.decodeIfPresent([AISourceProvenance].self, forKey: .sources) ?? []
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

    static func succeeded(
        callID: String,
        toolName: String,
        resultSummary: String? = nil,
        metadata: [String: String] = [:],
        sources: [AISourceProvenance] = []
    ) -> AIToolEvent {
        AIToolEvent(
            toolCallID: callID,
            toolName: toolName,
            phase: .succeeded,
            resultSummary: resultSummary,
            metadata: metadata,
            sources: sources
        )
    }

    static func failed(callID: String, toolName: String, error: String? = nil, metadata: [String: String] = [:]) -> AIToolEvent {
        AIToolEvent(toolCallID: callID, toolName: toolName, phase: .failed, errorMessage: error, metadata: metadata)
    }

    static func cancelled(callID: String, toolName: String) -> AIToolEvent {
        AIToolEvent(toolCallID: callID, toolName: toolName, phase: .cancelled)
    }
}
