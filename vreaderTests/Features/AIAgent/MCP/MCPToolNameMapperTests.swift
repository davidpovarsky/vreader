// Purpose: Unit tests for MCPToolNameMapper.
// Tests model-safe name mapping, collision resistance, character sanitization, and reversibility.

import Testing
import Foundation
@testable import vreader

@Suite("MCPToolNameMapperTests")
struct MCPToolNameMapperTests {

    @Test func mapsStandardServerAndToolNamesDeterministically() {
        let mapped = MCPToolNameMapper.map(serverPrefix: "fetch", originalToolName: "get_url")
        #expect(mapped == "mcp_fetch_get_url")

        let parsed = MCPToolNameMapper.parse(mappedToolName: mapped)
        #expect(parsed != nil)
        #expect(parsed?.serverPrefix == "fetch")
        #expect(parsed?.originalToolName == "get_url")
    }

    @Test func sanitizesSpecialAndInvalidCharacters() {
        let mapped = MCPToolNameMapper.map(serverPrefix: "my-server.v1", originalToolName: "fetch/data:now")
        // Hyphens, periods, slashes, colons mapped to underscores
        #expect(mapped.hasPrefix("mcp_"))
        #expect(!mapped.contains("/"))
        #expect(!mapped.contains(":"))
        #expect(!mapped.contains("."))
    }

    @Test func nonMCPNameReturnsNilOnParse() {
        #expect(MCPToolNameMapper.parse(mappedToolName: "search_current_book") == nil)
        #expect(MCPToolNameMapper.parse(mappedToolName: "other_tool") == nil)
    }

    @Test func boundedLengthPreventsExcessiveModelName() {
        let longServer = String(repeating: "a", count: 100)
        let longTool = String(repeating: "b", count: 100)
        let mapped = MCPToolNameMapper.map(serverPrefix: longServer, originalToolName: longTool)
        #expect(mapped.count <= 64)
    }
}
