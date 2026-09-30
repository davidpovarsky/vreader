// Purpose: Connection lifecycle and protocol compatibility status models for MCP servers.

import Foundation

enum MCPCompatibilityStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(serverInfo: String, protocolVersion: String, toolCount: Int)
    case authRequired(description: String)
    case error(message: String)
    case incompatible(reason: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayLabel: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected(let info, _, let count): return "Connected (\(info), \(count) tools)"
        case .authRequired: return "Authentication Required"
        case .error(let msg): return "Error: \(msg)"
        case .incompatible(let reason): return "Incompatible: \(reason)"
        }
    }
}
