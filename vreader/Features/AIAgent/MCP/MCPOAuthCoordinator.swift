// Purpose: OAuth 2.0 PKCE authorization coordinator for MCP servers.
// Manages PKCE code generation, state verification, token exchange, and Keychain storage.

import Foundation
import CryptoKit

actor MCPOAuthCoordinator {
    private let secretStore: MCPSecretStore
    private var pendingStates: [String: (verifier: String, profileID: UUID)] = [:]

    init(secretStore: MCPSecretStore = MCPSecretStore()) {
        self.secretStore = secretStore
    }

    /// Generates PKCE authorization parameters: state, code_verifier, code_challenge.
    func generateAuthorizationParameters(forProfileID profileID: UUID) -> (state: String, codeChallenge: String, verifier: String) {
        let state = UUID().uuidString
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        pendingStates[state] = (verifier: verifier, profileID: profileID)
        return (state: state, codeChallenge: challenge, verifier: verifier)
    }

    /// Handles authorization callback and completes token exchange.
    func handleCallback(
        state: String,
        code: String,
        tokenEndpoint: URL
    ) async throws {
        try Task.checkCancellation()
        guard let pending = pendingStates.removeValue(forKey: state) else {
            throw NSError(domain: "vreader.mcp.oauth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth state"])
        }

        // Token exchange request
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": pending.verifier
        ]
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "vreader.mcp.oauth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw NSError(domain: "vreader.mcp.oauth", code: 422, userInfo: [NSLocalizedDescriptionKey: "Malformed token response"])
        }

        let refreshToken = json["refresh_token"] as? String
        try secretStore.saveOAuthTokens(accessToken: accessToken, refreshToken: refreshToken, forProfileID: pending.profileID)
    }

    func cancelPending(forProfileID profileID: UUID) {
        pendingStates = pendingStates.filter { $0.value.profileID != profileID }
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
