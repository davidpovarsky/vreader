// Purpose: Data models for MCP (Model Context Protocol) server profiles.
// Strictly excludes secrets/tokens (which are stored exclusively in Keychain).

import Foundation

enum MCPAuthType: String, Sendable, Codable, Equatable {
    case none
    case bearerToken
    case oauth
}

struct MCPServerProfile: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var name: String
    var endpointURL: URL
    var isEnabled: Bool
    var authType: MCPAuthType
    var dateAdded: Date
    var lastConnected: Date?
    var discoveredToolCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        endpointURL: URL,
        isEnabled: Bool = true,
        authType: MCPAuthType = .none,
        dateAdded: Date = Date(),
        lastConnected: Date? = nil,
        discoveredToolCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.endpointURL = endpointURL
        self.isEnabled = isEnabled
        self.authType = authType
        self.dateAdded = dateAdded
        self.lastConnected = lastConnected
        self.discoveredToolCount = discoveredToolCount
    }

    /// Verifies endpoint transport security: HTTPS required for remote hosts; HTTP allowed only on loopback.
    var isSecureEndpoint: Bool {
        guard let scheme = endpointURL.scheme?.lowercased() else { return false }
        if scheme == "https" { return true }
        if scheme == "http" {
            let host = endpointURL.host?.lowercased() ?? ""
            return host == "localhost" || host == "127.0.0.1" || host == "::1"
        }
        return false
    }
}
