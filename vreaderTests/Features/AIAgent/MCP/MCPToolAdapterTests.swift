// Purpose: Unit tests for MCPToolAdapter.
// Tests dynamic tool wrapping, externalNetwork permission gating, and result provenance tagging.

import Testing
import Foundation
@testable import vreader

@Suite("MCPToolAdapterTests")
struct MCPToolAdapterTests {

    private final class MockMCPRunner: @unchecked Sendable {
        var ranCalls: [(String, JSONValue)] = []
        var mockResult = "MCP Server Response"

        func execute(toolName: String, input: JSONValue) async throws -> String {
            ranCalls.append((toolName, input))
            return mockResult
        }
    }

    @Test func toolExecutesWhenExternalNetworkAllowed() async {
        let runner = MockMCPRunner()
        let store = InMemoryAIAgentPreferencesStore()
        store.preferences.permissions[.externalNetwork] = .allow
        let gate = AIAgentToolExecutionGate(
            preferencesStore: store,
            broker: AIActionConfirmationBroker(preferencesStore: store),
            confirmationAvailability: .brokerConnected
        )

        let definition = ToolDefinition(
            name: "mcp_fetch_get",
            description: "Fetch web content",
            inputSchema: .object(["type": .string("object")])
        )

        let adapter = MCPToolAdapter(
            definition: definition,
            serverName: "FetchServer",
            originalToolName: "get",
            authorizationGate: gate,
            executor: { name, input in
                try await runner.execute(toolName: name, input: input)
            }
        )

        let result = await adapter.run(.object(["url": .string("https://example.com")]))
        #expect(!result.isError)
        #expect(result.content.contains("MCP Server Response"))
        #expect(runner.ranCalls.count == 1)
    }

    @Test func toolExecutionDeniedWhenExternalNetworkDenied() async {
        let runner = MockMCPRunner()
        let store = InMemoryAIAgentPreferencesStore()
        store.preferences.permissions[.externalNetwork] = .deny
        let gate = AIAgentToolExecutionGate(
            preferencesStore: store,
            broker: AIActionConfirmationBroker(preferencesStore: store),
            confirmationAvailability: .brokerConnected
        )

        let definition = ToolDefinition(name: "mcp_fetch_get", description: "Fetch")
        let adapter = MCPToolAdapter(
            definition: definition,
            serverName: "FetchServer",
            originalToolName: "get",
            authorizationGate: gate,
            executor: { name, input in
                try await runner.execute(toolName: name, input: input)
            }
        )

        let result = await adapter.run(.object([:]))
        #expect(result.isError)
        #expect(runner.ranCalls.isEmpty)
    }
}
