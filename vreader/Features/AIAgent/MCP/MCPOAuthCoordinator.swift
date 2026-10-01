// Purpose: OAuth 2.0 PKCE authorization coordinator for MCP servers.
// Manages PKCE code generation, state verification, ASWebAuthenticationSession browser flow,
// token exchange, token refresh, and Keychain storage.

import Foundation
import CryptoKit
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#endif

#if canImport(AuthenticationServices) && canImport(UIKit)
@MainActor
final class WebAuthPresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationAnchor()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#endif

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

    /// Launches an ASWebAuthenticationSession to authenticate the user and completes token exchange.
    @MainActor
    func startAuthorizationFlow(
        profileID: UUID,
        authorizationURL: URL,
        tokenEndpoint: URL,
        clientID: String,
        callbackScheme: String = "vreader-mcp-oauth"
    ) async throws {
        try Task.checkCancellation()
        let params = await generateAuthorizationParameters(forProfileID: profileID)

        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: true)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "response_type", value: "code"))
        queryItems.append(URLQueryItem(name: "client_id", value: clientID))
        queryItems.append(URLQueryItem(name: "redirect_uri", value: "\(callbackScheme)://callback"))
        queryItems.append(URLQueryItem(name: "state", value: params.state))
        queryItems.append(URLQueryItem(name: "code_challenge", value: params.codeChallenge))
        queryItems.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        components?.queryItems = queryItems

        guard let authURL = components?.url else {
            throw NSError(domain: "vreader.mcp.oauth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid authorization URL components"])
        }

#if canImport(AuthenticationServices) && canImport(UIKit)
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: NSError(domain: "vreader.mcp.oauth", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unknown authentication session error"]))
                }
            }
            #if os(iOS)
            session.presentationContextProvider = WebAuthPresentationAnchor.shared
            #endif
            session.start()
        }

        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value else {
            throw NSError(domain: "vreader.mcp.oauth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Callback URL missing code or state parameter"])
        }

        guard returnedState == params.state else {
            throw NSError(domain: "vreader.mcp.oauth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Returned state does not match expected state"])
        }

        try await handleCallback(state: returnedState, code: code, tokenEndpoint: tokenEndpoint)
#else
        throw NSError(domain: "vreader.mcp.oauth", code: 501, userInfo: [NSLocalizedDescriptionKey: "AuthenticationServices unavailable on this platform"])
#endif
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

    /// Refreshes the OAuth access token using the stored refresh token.
    func refreshToken(forProfileID profileID: UUID, tokenEndpoint: URL) async throws -> String {
        try Task.checkCancellation()
        guard let refreshToken = secretStore.fetchRefreshToken(forProfileID: profileID) else {
            throw NSError(domain: "vreader.mcp.oauth", code: 404, userInfo: [NSLocalizedDescriptionKey: "No refresh token available"])
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "vreader.mcp.oauth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Token refresh failed"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String else {
            throw NSError(domain: "vreader.mcp.oauth", code: 422, userInfo: [NSLocalizedDescriptionKey: "Malformed token refresh response"])
        }

        let newRefreshToken = json["refresh_token"] as? String ?? refreshToken
        try secretStore.saveOAuthTokens(accessToken: newAccessToken, refreshToken: newRefreshToken, forProfileID: profileID)
        return newAccessToken
    }

    /// Disconnects and removes all credentials for a profile.
    func logout(profileID: UUID) throws {
        cancelPending(forProfileID: profileID)
        try secretStore.deleteCredentials(forProfileID: profileID)
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
