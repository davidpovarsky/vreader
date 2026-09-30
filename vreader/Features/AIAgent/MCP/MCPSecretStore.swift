// Purpose: Secure Keychain-backed storage for MCP authentication tokens and client secrets.
// Never exposes secrets to logs, UserDefaults, or chat history.

import Foundation

struct MCPSecretStore: Sendable {
    private let keychain: KeychainService

    init(keychain: KeychainService = KeychainService(serviceIdentifier: "com.vreader.mcp.secrets")) {
        self.keychain = keychain
    }

    private func tokenAccount(for profileID: UUID) -> String {
        "mcp.token.\(profileID.uuidString)"
    }

    private func refreshTokenAccount(for profileID: UUID) -> String {
        "mcp.refresh.\(profileID.uuidString)"
    }

    func saveToken(_ token: String, forProfileID profileID: UUID) throws {
        try keychain.saveString(token, forAccount: tokenAccount(for: profileID))
    }

    func fetchToken(forProfileID profileID: UUID) -> String? {
        try? keychain.readString(forAccount: tokenAccount(for: profileID))
    }

    func deleteToken(forProfileID profileID: UUID) throws {
        try keychain.delete(forAccount: tokenAccount(for: profileID))
    }

    func saveOAuthTokens(accessToken: String, refreshToken: String?, forProfileID profileID: UUID) throws {
        try saveToken(accessToken, forProfileID: profileID)
        if let refreshToken {
            try keychain.saveString(refreshToken, forAccount: refreshTokenAccount(for: profileID))
        }
    }

    func fetchRefreshToken(forProfileID profileID: UUID) -> String? {
        try? keychain.readString(forAccount: refreshTokenAccount(for: profileID))
    }

    func deleteCredentials(forProfileID profileID: UUID) throws {
        try? keychain.delete(forAccount: tokenAccount(for: profileID))
        try? keychain.delete(forAccount: refreshTokenAccount(for: profileID))
    }
}
