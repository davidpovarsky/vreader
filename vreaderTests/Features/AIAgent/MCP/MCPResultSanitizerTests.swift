// Purpose: Unit tests for MCPResultSanitizer.
// Tests bounding payload sizes, text length limits, and deep JSON nesting defense.

import Testing
import Foundation
@testable import vreader

@Suite("MCPResultSanitizerTests")
struct MCPResultSanitizerTests {

    @Test func truncatesExcessivelyLongStrings() {
        let longString = String(repeating: "A", count: 20_000)
        let sanitized = MCPResultSanitizer.sanitizeText(longString, maxCharacters: 1_000)
        #expect(sanitized.count <= 1_003) // including ellipsis
        #expect(sanitized.hasSuffix("..."))
    }

    @Test func handlesNormalSizedStringsWithoutModification() {
        let text = "Normal size MCP tool response."
        let sanitized = MCPResultSanitizer.sanitizeText(text, maxCharacters: 1_000)
        #expect(sanitized == text)
    }

    @Test func boundsNestedJSONStructures() {
        // Deeply nested dict
        var deepDict: [String: JSONValue] = ["leaf": .string("value")]
        for i in 0..<15 {
            deepDict = ["level_\(i)": .object(deepDict)]
        }

        let sanitized = MCPResultSanitizer.sanitizeJSON(.object(deepDict), maxDepth: 4)
        #expect(sanitized != nil)
    }
}
