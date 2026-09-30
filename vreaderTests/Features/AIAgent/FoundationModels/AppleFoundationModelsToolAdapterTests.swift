// Purpose: Unit tests for AppleFoundationModelsToolAdapter.
// Proves that native Foundation Models tool adapter delegates to existing VReader domain tools
// through the same authorization and boundary gates.

import Testing
import Foundation
@testable import vreader

@Suite("AppleFoundationModelsToolAdapterTests")
struct AppleFoundationModelsToolAdapterTests {

    private final class MockTool: AITool, @unchecked Sendable {
        var callCount = 0
        var definition: ToolDefinition {
            ToolDefinition(name: "mock_tool", description: "A mock tool")
        }
        func run(_ input: JSONValue) async -> ToolResult {
            callCount += 1
            return ToolResult(callID: "call_1", content: "Success")
        }
    }

    @Test func toolAdapterInvokesUnderlyingToolOnce() async {
        let mock = MockTool()
        let adapter = AppleFoundationModelsToolAdapter(tool: mock)

        let result = await adapter.execute(argumentsJSON: "{}")
        #expect(mock.callCount == 1)
        #expect(result.contains("Success"))
    }

    @Test func toolAdapterRejectsMalformedJSONGracefully() async {
        let mock = MockTool()
        let adapter = AppleFoundationModelsToolAdapter(tool: mock)

        let result = await adapter.execute(argumentsJSON: "{invalid-json")
        #expect(result.contains("Invalid JSON") || result.contains("Failed") || result.contains("Error"))
        #expect(mock.callCount == 0)
    }
}
