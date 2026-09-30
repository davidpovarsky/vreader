// Purpose: Display-safe compacted tool trace representation.
// Suitable for UI rendering in chat message clusters and backward-compatible persistence.

import Foundation

struct AIToolTrace: Identifiable, Sendable, Equatable, Codable {
    let id: UUID
    let toolCallID: String
    let toolName: String
    let displayName: String
    let iconName: String
    let category: AIToolCategory
    var state: AIToolLifecycleState
    var argumentSummary: String
    var resultSummary: String
    var isError: Bool
    let startTime: Date
    var endTime: Date?
    var mcpServerName: String?
    var mutationRecordID: String?

    init(
        id: UUID = UUID(),
        toolCallID: String,
        toolName: String,
        displayName: String? = nil,
        iconName: String? = nil,
        category: AIToolCategory? = nil,
        state: AIToolLifecycleState = .queued,
        argumentSummary: String = "",
        resultSummary: String = "",
        isError: Bool = false,
        startTime: Date = Date(),
        endTime: Date? = nil,
        mcpServerName: String? = nil,
        mutationRecordID: String? = nil
    ) {
        let meta = AIToolDisplayMetadata.metadata(for: toolName)
        self.id = id
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.displayName = displayName ?? meta.defaultDisplayName
        self.iconName = iconName ?? meta.iconName
        self.category = category ?? meta.category
        self.state = state
        self.argumentSummary = argumentSummary
        self.resultSummary = resultSummary
        self.isError = isError
        self.startTime = startTime
        self.endTime = endTime
        self.mcpServerName = mcpServerName
        self.mutationRecordID = mutationRecordID
    }

    mutating func update(with event: AIToolEvent) {
        self.state = event.phase
        if let arg = event.argumentSummary, !arg.isEmpty {
            self.argumentSummary = arg
        }
        if let res = event.resultSummary, !res.isEmpty {
            self.resultSummary = res
        }
        if let err = event.errorMessage, !err.isEmpty {
            self.resultSummary = err
            self.isError = true
        } else if event.phase == .succeeded {
            self.isError = false
        } else if event.phase == .failed {
            self.isError = true
        }
        if event.phase.isTerminal && self.endTime == nil {
            self.endTime = event.timestamp
        }
        if let server = event.metadata["mcpServerName"] {
            self.mcpServerName = server
        }
        if let recordID = event.metadata["mutationRecordID"] {
            self.mutationRecordID = recordID
        }
    }

    static func traces(from events: [AIToolEvent]) -> [AIToolTrace] {
        var tracesByCallID: [String: AIToolTrace] = [:]
        var callOrder: [String] = []

        for event in events {
            if tracesByCallID[event.toolCallID] == nil {
                callOrder.append(event.toolCallID)
                var trace = AIToolTrace(
                    toolCallID: event.toolCallID,
                    toolName: event.toolName,
                    state: event.phase,
                    argumentSummary: event.argumentSummary ?? "",
                    resultSummary: event.resultSummary ?? "",
                    startTime: event.timestamp
                )
                trace.update(with: event)
                tracesByCallID[event.toolCallID] = trace
            } else {
                tracesByCallID[event.toolCallID]?.update(with: event)
            }
        }
        return callOrder.compactMap { tracesByCallID[$0] }
    }
}
