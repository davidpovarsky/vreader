// Purpose: Represents an active connection to an MCP server over HTTP transport using official MCP Swift SDK.
// Encapsulates tool listing, tool invocation, connection state, and clean disconnect.

import Foundation
import OSLog
#if canImport(MCP)
import MCP
#endif

final class HTTPMCPConnection: MCPConnecting, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.vreader.app", category: "HTTPMCPConnection")

    let profile: MCPServerProfile
    private let secretStore: MCPSecretStore
    private let lock = NSLock()
    private var _status: MCPCompatibilityStatus = .disconnected

#if canImport(MCP)
    private var client: Client?
    private var transport: HTTPClientTransport?
#endif

    init(profile: MCPServerProfile, secretStore: MCPSecretStore = MCPSecretStore()) {
        self.profile = profile
        self.secretStore = secretStore
    }

    var status: MCPCompatibilityStatus {
        lock.withLock { _status }
    }

    func connect() async throws {
        try Task.checkCancellation()
        guard profile.isSecureEndpoint else {
            let error = NSError(domain: "vreader.mcp", code: 403, userInfo: [NSLocalizedDescriptionKey: "Insecure endpoint. HTTPS required for remote MCP servers."])
            lock.withLock { _status = .error(message: error.localizedDescription) }
            throw error
        }

        lock.withLock { _status = .connecting }

#if canImport(MCP)
        do {
            let transport = HTTPClientTransport(endpoint: profile.endpointURL)
            let client = Client(name: "vreader", version: "1.0.0")
            try await client.connect(transport: transport)

            self.transport = transport
            self.client = client

            let (tools, _) = try await client.listTools()
            lock.withLock {
                _status = .connected(serverInfo: profile.name, protocolVersion: "2024-11-05", toolCount: tools.count)
            }
        } catch {
            lock.withLock {
                _status = .error(message: error.localizedDescription)
            }
            throw error
        }
#else
        lock.withLock {
            _status = .error(message: "MCP framework unavailable on this platform.")
        }
        throw NSError(domain: "vreader.mcp", code: 501, userInfo: [NSLocalizedDescriptionKey: "MCP framework unavailable on this platform."])
#endif
    }

    func disconnect() async {
#if canImport(MCP)
        if let client = self.client {
            await client.disconnect()
        }
        self.client = nil
        self.transport = nil
#endif
        lock.withLock {
            _status = .disconnected
        }
    }

    func listTools() async throws -> [ToolDefinition] {
        try Task.checkCancellation()
#if canImport(MCP)
        guard let client = self.client else {
            throw NSError(domain: "vreader.mcp", code: 404, userInfo: [NSLocalizedDescriptionKey: "MCP client not connected."])
        }
        let (tools, _) = try await client.listTools()
        return tools.map { tool in
            let schemaValue: JSONValue
            if let schemaData = try? JSONEncoder().encode(tool.inputSchema),
               let decoded = try? JSONDecoder().decode(JSONValue.self, from: schemaData) {
                schemaValue = decoded
            } else {
                schemaValue = .object(["type": .string("object")])
            }
            return ToolDefinition(
                name: tool.name,
                description: tool.description ?? "",
                inputSchema: schemaValue
            )
        }
#else
        throw NSError(domain: "vreader.mcp", code: 501, userInfo: [NSLocalizedDescriptionKey: "MCP framework unavailable on this platform."])
#endif
    }

    #if canImport(MCP)
    private func toMCPValue(_ json: JSONValue) -> Value {
        switch json {
        case .null:
            return .null
        case .bool(let b):
            return .bool(b)
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 && n >= Double(Int.min) && n <= Double(Int.max) {
                return .int(Int(n))
            } else {
                return .double(n)
            }
        case .string(let s):
            return .string(s)
        case .array(let arr):
            return .array(arr.map(toMCPValue))
        case .object(let dict):
            return .object(dict.mapValues(toMCPValue))
        }
    }
    #endif

    func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        try Task.checkCancellation()
#if canImport(MCP)
        guard let client = self.client else {
            throw NSError(domain: "vreader.mcp", code: 404, userInfo: [NSLocalizedDescriptionKey: "MCP client not connected."])
        }
        var mcpArgs: [String: Value] = [:]
        if case .object(let dict) = arguments {
            mcpArgs = dict.mapValues(toMCPValue)
        }
        let (content, isError) = try await client.callTool(name: name, arguments: mcpArgs)
        if isError {
            let errorText = content.compactMap { block -> String? in
                if case .text(let t) = block { return t }
                return nil
            }.joined(separator: "\n")
            throw NSError(domain: "vreader.mcp", code: 500, userInfo: [NSLocalizedDescriptionKey: errorText.isEmpty ? "MCP tool call returned error" : errorText])
        }
        let textBlocks = content.compactMap { block -> String? in
            if case .text(let t) = block { return t }
            return nil
        }
        return .object(["result": .string(textBlocks.joined(separator: "\n"))])
#else
        throw NSError(domain: "vreader.mcp", code: 501, userInfo: [NSLocalizedDescriptionKey: "MCP framework unavailable on this platform."])
#endif
    }
}
