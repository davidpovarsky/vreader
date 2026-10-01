// Purpose: Central actor managing MCP server connection lifecycles, credentials, and tool discovery.

import Foundation
import OSLog

actor MCPClientManager {
    static let shared = MCPClientManager()
    private static let log = Logger(subsystem: "com.vreader.app", category: "MCPClientManager")

    typealias ConnectionFactory = @Sendable (MCPServerProfile) -> any MCPConnecting

    private let profileStore: MCPServerProfileStore
    private let secretStore: MCPSecretStore
    private let connectionFactory: ConnectionFactory
    private var activeConnections: [UUID: any MCPConnecting] = [:]
    private var connectionStatuses: [UUID: MCPCompatibilityStatus] = [:]

    init(
        profileStore: MCPServerProfileStore = MCPServerProfileStore.shared,
        secretStore: MCPSecretStore = MCPSecretStore(),
        connectionFactory: @escaping ConnectionFactory = { profile in
            HTTPMCPConnection(profile: profile)
        }
    ) {
        self.profileStore = profileStore
        self.secretStore = secretStore
        self.connectionFactory = connectionFactory
    }

    func status(for profileID: UUID) -> MCPCompatibilityStatus {
        connectionStatuses[profileID] ?? .disconnected
    }

    /// Registers a custom connection provider (useful in tests).
    func registerConnection(_ connection: any MCPConnecting, for profileID: UUID) {
        activeConnections[profileID] = connection
        connectionStatuses[profileID] = connection.status
    }

    /// Tests connection and discovers available tools for a profile.
    func testConnection(for profile: MCPServerProfile) async throws -> [ToolDefinition] {
        guard profile.isSecureEndpoint else {
            throw NSError(domain: "vreader.mcp", code: 403, userInfo: [NSLocalizedDescriptionKey: "Insecure endpoint. HTTPS required for remote MCP servers."])
        }

        connectionStatuses[profile.id] = .connecting

        let connection: any MCPConnecting
        if let existing = activeConnections[profile.id] {
            connection = existing
        } else {
            connection = connectionFactory(profile)
            activeConnections[profile.id] = connection
        }

        do {
            try await connection.connect()
            let tools = try await connection.listTools()
            connectionStatuses[profile.id] = .connected(serverInfo: profile.name, protocolVersion: "2024-11-05", toolCount: tools.count)
            return tools
        } catch {
            connectionStatuses[profile.id] = .error(message: error.localizedDescription)
            throw error
        }
    }

    func disconnect(profileID: UUID) async {
        if let connection = activeConnections.removeValue(forKey: profileID) {
            await connection.disconnect()
        }
        connectionStatuses[profileID] = .disconnected
    }

    /// Discovers tools across all enabled profiles.
    func discoverEnabledTools() async -> [(profile: MCPServerProfile, tool: ToolDefinition)] {
        let profiles = await profileStore.allProfiles().filter { $0.isEnabled && $0.isSecureEndpoint }
        var discovered: [(profile: MCPServerProfile, tool: ToolDefinition)] = []

        for profile in profiles {
            if let connection = activeConnections[profile.id], connection.status.isConnected {
                if let tools = try? await connection.listTools() {
                    for t in tools {
                        discovered.append((profile: profile, tool: t))
                    }
                }
            }
        }
        return discovered
    }

    /// Invokes a remote tool on the specified profile.
    func invokeTool(
        profileID: UUID,
        toolName: String,
        arguments: JSONValue
    ) async throws -> JSONValue {
        guard let connection = activeConnections[profileID] else {
            throw NSError(domain: "vreader.mcp", code: 404, userInfo: [NSLocalizedDescriptionKey: "Server connection not found or disconnected"])
        }
        return try await connection.callTool(name: toolName, arguments: arguments)
    }
}
