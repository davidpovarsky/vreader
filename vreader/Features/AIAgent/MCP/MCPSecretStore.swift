// Purpose: Secure Keychain-backed storage for MCP authentication tokens and client secrets.
// Binds tokens to profileID and endpoint origin so endpoint changes do not reuse credentials.
// Never exposes secrets to logs, UserDefaults, or chat history.

import Foundation

struct MCPSecretStore: Sendable {
    private let keychain: KeychainService

    init(keychain: KeychainService = KeychainService(serviceIdentifier: "com.vreader.mcp.secrets")) {
        self.keychain = keychain
    }

    init(serviceName: String) {
        self.init(keychain: KeychainService(serviceIdentifier: serviceName))
    }

    private func tokenAccount(for profileID: UUID, endpoint: URL? = nil) -> String {
        let host = endpoint?.host?.lowercased() ?? "default"
        return "mcp.token.\(profileID.uuidString).\(host)"
    }

    private func refreshTokenAccount(for profileID: UUID, endpoint: URL? = nil) -> String {
        let host = endpoint?.host?.lowercased() ?? "default"
        return "mcp.refresh.\(profileID.uuidString).\(host)"
    }

    func saveToken(_ token: String, forProfileID profileID: UUID, endpoint: URL? = nil) throws {
        try keychain.saveString(token, forAccount: tokenAccount(for: profileID, endpoint: endpoint))
    }

    func saveToken(_ token: String, for profileID: UUID, endpointURL: URL? = nil) throws {
        try saveToken(token, forProfileID: profileID, endpoint: endpointURL)
    }

    func fetchToken(forProfileID profileID: UUID, endpoint: URL? = nil) -> String? {
        try? keychain.readString(forAccount: tokenAccount(for: profileID, endpoint: endpoint))
    }

    func token(for profileID: UUID, endpointURL: URL? = nil) throws -> String? {
        fetchToken(forProfileID: profileID, endpoint: endpointURL)
    }

    func deleteToken(forProfileID profileID: UUID, endpoint: URL? = nil) throws {
        try keychain.delete(forAccount: tokenAccount(for: profileID, endpoint: endpoint))
    }

    func deleteToken(for profileID: UUID, endpointURL: URL? = nil) throws {
        try deleteToken(forProfileID: profileID, endpoint: endpointURL)
    }

    func saveOAuthTokens(accessToken: String, refreshToken: String?, forProfileID profileID: UUID, endpoint: URL? = nil) throws {
        try saveToken(accessToken, forProfileID: profileID, endpoint: endpoint)
        if let refreshToken {
            try keychain.saveString(refreshToken, forAccount: refreshTokenAccount(for: profileID, endpoint: endpoint))
        }
    }

    func fetchRefreshToken(forProfileID profileID: UUID, endpoint: URL? = nil) -> String? {
        try? keychain.readString(forAccount: refreshTokenAccount(for: profileID, endpoint: endpoint))
    }

    func deleteCredentials(forProfileID profileID: UUID, endpoint: URL? = nil) throws {
        try? keychain.delete(forAccount: tokenAccount(for: profileID, endpoint: endpoint))
        try? keychain.delete(forAccount: refreshTokenAccount(for: profileID, endpoint: endpoint))
    }
}
