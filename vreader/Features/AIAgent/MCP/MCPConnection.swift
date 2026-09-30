// Purpose: Represents an active connection to an MCP server over HTTP/SSE.
// Encapsulates tool listing, tool invocation, and ping/keepalive.

import Foundation

protocol MCPConnecting: Sendable {
    var profile: MCPServerProfile { get }
    var status: MCPCompatibilityStatus { get }
    func connect() async throws
    func disconnect() async
    func listTools() async throws -> [ToolDefinition]
    func callTool(name: String, arguments: JSONValue) async throws -> JSONValue
}

actor MockMCPConnection: MCPConnecting {
    let profile: MCPServerProfile
    private(set) var status: MCPCompatibilityStatus = .disconnected
    private let mockTools: [ToolDefinition]

    init(profile: MCPServerProfile, mockTools: [ToolDefinition] = []) {
        self.profile = profile
        self.mockTools = mockTools
    }

    func connect() async throws {
        try Task.checkCancellation()
        status = .connected(serverInfo: profile.name, protocolVersion: "2024-11-05", toolCount: mockTools.count)
    }

    func disconnect() async {
        status = .disconnected
    }

    func listTools() async throws -> [ToolDefinition] {
        try Task.checkCancellation()
        return mockTools
    }

    func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        try Task.checkCancellation()
        return .object(["result": .string("Mock MCP output for \(name)")])
    }
}
