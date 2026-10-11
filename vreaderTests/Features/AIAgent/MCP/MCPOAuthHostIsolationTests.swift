// Purpose: Focused test suite for MCP OAuth origin-bound credential storage.
// Proves tokens are bound to MCP resource endpoint rather than OAuth authorization server endpoint,
// preventing token leaks and guaranteeing correct Bearer header injection across host boundaries.

import Testing
import Foundation
@testable import vreader

@Suite("MCPOAuthHostIsolationTests")
struct MCPOAuthHostIsolationTests {

    @Test func canonicalOriginNormalizesDefaultPortsAndIsolatesSchemeHostPortAndProfile() throws {
        let uniqueService = "test-mcp-origin-\(UUID().uuidString)"
        let secretStore = MCPSecretStore(serviceName: uniqueService)

        let profileA = UUID()
        let profileB = UUID()

        let httpsImplicit443 = try #require(URL(string: "https://Example.COM/mcp"))
        let httpsExplicit443 = try #require(URL(string: "https://example.com:443/mcp/v2"))
        let httpsCustom8443 = try #require(URL(string: "https://example.com:8443/mcp"))
        let httpImplicit80 = try #require(URL(string: "http://example.com/mcp"))
        let httpExplicit80 = try #require(URL(string: "http://example.com:80/other"))

        // 1. Default port normalization: https://example.com/mcp == https://example.com:443/mcp
        #expect(MCPSecretStore.canonicalOrigin(for: httpsImplicit443) == "https://example.com:443")
        #expect(MCPSecretStore.canonicalOrigin(for: httpsExplicit443) == "https://example.com:443")
        #expect(MCPSecretStore.canonicalOrigin(for: httpsCustom8443) == "https://example.com:8443")
        #expect(MCPSecretStore.canonicalOrigin(for: httpImplicit80) == "http://example.com:80")
        #expect(MCPSecretStore.canonicalOrigin(for: httpExplicit80) == "http://example.com:80")

        try secretStore.saveToken("tok-443", forProfileID: profileA, endpoint: httpsImplicit443)
        try secretStore.saveRefreshToken("ref-443", forProfileID: profileA, endpoint: httpsImplicit443)
        defer {
            secretStore.deleteCredentials(forProfileID: profileA, endpoint: httpsImplicit443)
            secretStore.deleteCredentials(forProfileID: profileA, endpoint: httpsCustom8443)
            secretStore.deleteCredentials(forProfileID: profileA, endpoint: httpImplicit80)
            secretStore.deleteCredentials(forProfileID: profileB, endpoint: httpsImplicit443)
        }

        #expect(secretStore.fetchToken(forProfileID: profileA, endpoint: httpsExplicit443) == "tok-443")
        #expect(secretStore.fetchRefreshToken(forProfileID: profileA, endpoint: httpsExplicit443) == "ref-443")

        // 2. Port isolation: :443 vs :8443 for the same profileID
        #expect(secretStore.fetchToken(forProfileID: profileA, endpoint: httpsCustom8443) == nil)
        #expect(secretStore.fetchRefreshToken(forProfileID: profileA, endpoint: httpsCustom8443) == nil)

        try secretStore.saveToken("tok-8443", forProfileID: profileA, endpoint: httpsCustom8443)
        try secretStore.saveRefreshToken("ref-8443", forProfileID: profileA, endpoint: httpsCustom8443)

        #expect(secretStore.fetchToken(forProfileID: profileA, endpoint: httpsCustom8443) == "tok-8443")
        #expect(secretStore.fetchRefreshToken(forProfileID: profileA, endpoint: httpsCustom8443) == "ref-8443")
        #expect(secretStore.fetchToken(forProfileID: profileA, endpoint: httpsImplicit443) == "tok-443")
        #expect(secretStore.fetchRefreshToken(forProfileID: profileA, endpoint: httpsImplicit443) == "ref-443")

        // 3. Scheme isolation: https://example.com/mcp vs http://example.com/mcp for the same profileID
        #expect(secretStore.fetchToken(forProfileID: profileA, endpoint: httpImplicit80) == nil)
        #expect(secretStore.fetchRefreshToken(forProfileID: profileA, endpoint: httpImplicit80) == nil)

        try secretStore.saveToken("tok-http-80", forProfileID: profileA, endpoint: httpImplicit80)
        try secretStore.saveRefreshToken("ref-http-80", forProfileID: profileA, endpoint: httpImplicit80)

        #expect(secretStore.fetchToken(forProfileID: profileA, endpoint: httpExplicit80) == "tok-http-80")
        #expect(secretStore.fetchRefreshToken(forProfileID: profileA, endpoint: httpExplicit80) == "ref-http-80")
        #expect(secretStore.fetchToken(forProfileID: profileA, endpoint: httpsImplicit443) == "tok-443")

        // 4. Profile isolation on the exact same origin
        #expect(secretStore.fetchToken(forProfileID: profileB, endpoint: httpsImplicit443) == nil)
        #expect(secretStore.fetchRefreshToken(forProfileID: profileB, endpoint: httpsImplicit443) == nil)
    }

    @Test func oAuthTokenStoredUnderResourceEndpointWithCustomPortIsFoundByHTTPConnection() async throws {
        let uniqueService = "test-mcp-oauth-\(UUID().uuidString)"
        let secretStore = MCPSecretStore(serviceName: uniqueService)
        let coordinator = MCPOAuthCoordinator(secretStore: secretStore)

        let profileID = UUID()
        let resourceURL = try #require(URL(string: "https://mcp.example.com:8443/mcp"))
        let defaultPortOnSameHost = try #require(URL(string: "https://mcp.example.com:443/mcp"))
        let tokenURL = try #require(URL(string: "https://auth.example.com/oauth/token"))

        defer {
            secretStore.deleteCredentials(forProfileID: profileID, endpoint: resourceURL)
        }

        // 1. Generate parameters bound to resource endpoint with custom port :8443
        let params = await coordinator.generateAuthorizationParameters(
            forProfileID: profileID,
            resourceEndpoint: resourceURL,
            tokenEndpoint: tokenURL,
            clientID: "vreader-client"
        )

        // 2. Simulate token exchange callback returning access + refresh token
        let tokenJSON: [String: Any] = [
            "access_token": "token-for-mcp-8443",
            "refresh_token": "refresh-for-mcp-8443",
            "token_type": "Bearer",
            "expires_in": 3600
        ]
        let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON)

        try await coordinator.handleCallback(
            state: params.state,
            code: "auth-code-xyz",
            responseData: tokenData
        )

        // 3. Verify HTTPMCPConnection accessing https://mcp.example.com:8443/mcp finds the token and injects Bearer header
        let tokenFetched = try secretStore.token(for: profileID, endpointURL: resourceURL)
        #expect(tokenFetched == "token-for-mcp-8443")
        #expect(secretStore.fetchRefreshToken(forProfileID: profileID, endpoint: resourceURL) == "refresh-for-mcp-8443")

        let profile8443 = MCPServerProfile(
            id: profileID,
            name: "MCP 8443",
            endpointURL: resourceURL,
            transportKind: .streamableHTTP,
            authKind: .oauth,
            isEnabled: true
        )
        let conn8443 = HTTPMCPConnection(profile: profile8443, secretStore: secretStore)
        let config8443 = await conn8443.makeSessionConfiguration()
        #expect(config8443.httpAdditionalHeaders?["Authorization"] as? String == "Bearer token-for-mcp-8443")

        // 4. Verify token is NOT accessible under :443 on same host, auth.example.com, or another host
        #expect(try secretStore.token(for: profileID, endpointURL: defaultPortOnSameHost) == nil)
        #expect(secretStore.fetchRefreshToken(forProfileID: profileID, endpoint: defaultPortOnSameHost) == nil)

        let profile443 = MCPServerProfile(
            id: profileID,
            name: "MCP 443",
            endpointURL: defaultPortOnSameHost,
            transportKind: .streamableHTTP,
            authKind: .oauth,
            isEnabled: true
        )
        let conn443 = HTTPMCPConnection(profile: profile443, secretStore: secretStore)
        let config443 = await conn443.makeSessionConfiguration()
        #expect(config443.httpAdditionalHeaders?["Authorization"] == nil)

        let authHostToken = try secretStore.token(for: profileID, endpointURL: tokenURL)
        #expect(authHostToken == nil)

        let differentResourceURL = try #require(URL(string: "https://other-mcp.org:8443/sse"))
        let otherToken = try secretStore.token(for: profileID, endpointURL: differentResourceURL)
        #expect(otherToken == nil)

        // 5. Test Refresh Token Rotation under resource endpoint :8443
        let rotatedJSON: [String: Any] = [
            "access_token": "token-for-mcp-rotated-999",
            "refresh_token": "refresh-for-mcp-rotated-888",
            "token_type": "Bearer"
        ]
        let rotatedData = try JSONSerialization.data(withJSONObject: rotatedJSON)

        let rotatedToken = try await coordinator.refreshToken(
            forProfileID: profileID,
            resourceEndpoint: resourceURL,
            tokenEndpoint: tokenURL,
            responseData: rotatedData
        )
        #expect(rotatedToken == "token-for-mcp-rotated-999")

        let newFetched = try secretStore.token(for: profileID, endpointURL: resourceURL)
        #expect(newFetched == "token-for-mcp-rotated-999")

        let newRefresh = secretStore.fetchRefreshToken(forProfileID: profileID, endpoint: resourceURL)
        #expect(newRefresh == "refresh-for-mcp-rotated-888")

        // 6. Logout deletes both access and refresh credentials
        try await coordinator.logout(profileID: profileID, resourceEndpoint: resourceURL)
        #expect(try secretStore.token(for: profileID, endpointURL: resourceURL) == nil)
        #expect(secretStore.fetchRefreshToken(forProfileID: profileID, endpoint: resourceURL) == nil)
    }
}
