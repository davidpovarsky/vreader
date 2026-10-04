// Purpose: Secure Keychain-backed storage for MCP authentication tokens and client secrets.
// Binds tokens to profileID and endpoint origin so endpoint changes do not reuse credentials.
// Never exposes secrets to logs, UserDefaults, or chat history.

import Foundation

struct MCPSecretStore: Sendable {
    private let keychain: KeychainService

    private static let fallbackLock = NSLock()
    private static var inMemoryFallback: [String: String] = [:]

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
        let account = tokenAccount(for: profileID, endpoint: endpoint)
        do {
            try keychain.saveString(token, forAccount: account)
        } catch let KeychainError.unexpectedStatus(status) where status == -34018 {
            Self.fallbackLock.lock()
            defer { Self.fallbackLock.unlock() }
            Self.inMemoryFallback[account] = token
        }
    }

    func saveToken(_ token: String, for profileID: UUID, endpointURL: URL? = nil) throws {
        try saveToken(token, forProfileID: profileID, endpoint: endpointURL)
    }

    func fetchToken(forProfileID profileID: UUID, endpoint: URL? = nil) -> String? {
        let account = tokenAccount(for: profileID, endpoint: endpoint)
        if let val = try? keychain.readString(forAccount: account) {
            return val
        }
        Self.fallbackLock.lock()
        defer { Self.fallbackLock.unlock() }
        return Self.inMemoryFallback[account]
    }

    func token(for profileID: UUID, endpointURL: URL? = nil) throws -> String? {
        fetchToken(forProfileID: profileID, endpoint: endpointURL)
    }

    func deleteToken(forProfileID profileID: UUID, endpoint: URL? = nil) throws {
        let account = tokenAccount(for: profileID, endpoint: endpoint)
        try? keychain.delete(forAccount: account)
        Self.fallbackLock.lock()
        defer { Self.fallbackLock.unlock() }
        Self.inMemoryFallback.removeValue(forKey: account)
    }

    func deleteToken(for profileID: UUID, endpointURL: URL? = nil) throws {
        try deleteToken(forProfileID: profileID, endpoint: endpointURL)
    }

    func saveOAuthTokens(accessToken: String, refreshToken: String?, forProfileID profileID: UUID, endpoint: URL? = nil) throws {
        try saveToken(accessToken, forProfileID: profileID, endpoint: endpoint)
        if let refreshToken {
            let refreshAcct = refreshTokenAccount(for: profileID, endpoint: endpoint)
            do {
                try keychain.saveString(refreshToken, forAccount: refreshAcct)
            } catch let KeychainError.unexpectedStatus(status) where status == -34018 {
                Self.fallbackLock.lock()
                defer { Self.fallbackLock.unlock() }
                Self.inMemoryFallback[refreshAcct] = refreshToken
            }
        }
    }

    func fetchRefreshToken(forProfileID profileID: UUID, endpoint: URL? = nil) -> String? {
        let refreshAcct = refreshTokenAccount(for: profileID, endpoint: endpoint)
        if let val = try? keychain.readString(forAccount: refreshAcct) {
            return val
        }
        Self.fallbackLock.lock()
        defer { Self.fallbackLock.unlock() }
        return Self.inMemoryFallback[refreshAcct]
    }

    func deleteCredentials(forProfileID profileID: UUID, endpoint: URL? = nil) throws {
        try deleteToken(forProfileID: profileID, endpoint: endpoint)
        let refreshAcct = refreshTokenAccount(for: profileID, endpoint: endpoint)
        try? keychain.delete(forAccount: refreshAcct)
        Self.fallbackLock.lock()
        defer { Self.fallbackLock.unlock() }
        Self.inMemoryFallback.removeValue(forKey: refreshAcct)
    }
}
