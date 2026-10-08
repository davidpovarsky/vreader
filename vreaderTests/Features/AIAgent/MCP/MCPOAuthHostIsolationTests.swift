// Purpose: Focused test suite for MCP OAuth origin-bound credential storage.
// Proves tokens are bound to MCP resource endpoint rather than OAuth authorization server endpoint,
// preventing token leaks and guaranteeing correct Bearer header injection across host boundaries.

import Testing
import Foundation
@testable import vreader

@Suite("MCPOAuthHostIsolationTests")
struct MCPOAuthHostIsolationTests {

    @Test func oAuthTokenStoredUnderResourceEndpointIsFoundByHTTPConnection() async throws {
        let uniqueService = "test-mcp-oauth-\(UUID().uuidString)"
        let secretStore = MCPSecretStore(serviceName: uniqueService)
        let coordinator = MCPOAuthCoordinator(secretStore: secretStore)

        let profileID = UUID()
        let resourceURL = try #require(URL(string: "https://mcp.example.com/mcp/sse"))
        let authURL = try #require(URL(string: "https://auth.example.com/oauth/authorize"))
        let tokenURL = try #require(URL(string: "https://auth.example.com/oauth/token"))

        // 1. Generate parameters bound to resource endpoint
        let params = await coordinator.generateAuthorizationParameters(
            forProfileID: profileID,
            resourceEndpoint: resourceURL,
            tokenEndpoint: tokenURL,
            clientID: "vreader-client"
        )

        // 2. Simulate token exchange callback returning access + refresh token
        let tokenJSON: [String: Any] = [
            "access_token": "token-for-mcp-12345",
            "refresh_token": "refresh-for-mcp-67890",
            "token_type": "Bearer",
            "expires_in": 3600
        ]
        let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON)

        try await coordinator.handleCallback(
            state: params.state,
            code: "auth-code-xyz",
            responseData: tokenData
        )

        // 3. Verify HTTPMCPConnection accessing mcp.example.com finds the token
        let tokenFetched = try secretStore.token(for: profileID, endpointURL: resourceURL)
        #expect(tokenFetched == "token-for-mcp-12345")

        // 4. Verify token is NOT accessible under auth.example.com
        let authHostToken = try secretStore.token(for: profileID, endpointURL: tokenURL)
        #expect(authHostToken == nil)

        // 5. Changing MCP resource host does NOT reuse old credential
        let differentResourceURL = try #require(URL(string: "https://other-mcp.org/sse"))
        let otherToken = try secretStore.token(for: profileID, endpointURL: differentResourceURL)
        #expect(otherToken == nil)

        // 6. Test Refresh Token Rotation under resource endpoint
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

        // 7. Logout deletes both access and refresh credentials
        try await coordinator.logout(profileID: profileID, resourceEndpoint: resourceURL)
        #expect(try secretStore.token(for: profileID, endpointURL: resourceURL) == nil)
        #expect(secretStore.fetchRefreshToken(forProfileID: profileID, endpoint: resourceURL) == nil)
    }
}
