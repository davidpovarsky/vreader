// Purpose: Sanitization and bounds enforcement for external MCP tool results.
// Treats all external server content as untrusted DATA, bounding payload size and nesting depth.

import Foundation

struct MCPResultSanitizer: Sendable {
    let maxPayloadBytes: Int
    let maxTextCharacters: Int
    let maxNestingDepth: Int
    let maxCollectionCount: Int

    init(
        maxPayloadBytes: Int = 16_000,
        maxTextCharacters: Int = 8_000,
        maxNestingDepth: Int = 8,
        maxCollectionCount: Int = 100
    ) {
        self.maxPayloadBytes = max(1_000, maxPayloadBytes)
        self.maxTextCharacters = max(500, maxTextCharacters)
        self.maxNestingDepth = max(3, maxNestingDepth)
        self.maxCollectionCount = max(10, maxCollectionCount)
    }

    /// Sanitizes an arbitrary JSONValue received from an MCP tool call.
    func sanitize(_ value: JSONValue, currentDepth: Int = 0) -> JSONValue {
        guard currentDepth < maxNestingDepth else {
            return .string("[Truncated: max nesting depth reached]")
        }

        switch value {
        case .string(let str):
            if str.count > maxTextCharacters {
                return .string(String(str.prefix(maxTextCharacters)) + "\n[Truncated: character limit reached]")
            }
            return .string(str)

        case .number(let n):
            return n.isFinite ? .number(n) : .null

        case .bool(let b):
            return .bool(b)

        case .null:
            return .null

        case .array(let arr):
            let bounded = arr.prefix(maxCollectionCount)
            let sanitized = bounded.map { sanitize($0, currentDepth: currentDepth + 1) }
            return .array(sanitized)

        case .object(let dict):
            var sanitized: [String: JSONValue] = [:]
            for (k, v) in dict.prefix(maxCollectionCount) {
                // Strip potential secret keys if returned by server
                let lowerK = k.lowercased()
                if lowerK.contains("token") || lowerK.contains("secret") || lowerK.contains("password") {
                    sanitized[k] = .string("[Redacted credential]")
                } else {
                    sanitized[k] = sanitize(v, currentDepth: currentDepth + 1)
                }
            }
            return .object(sanitized)
        }
    }

    /// Converts and bounds a sanitized JSONValue to a model-facing ToolResult string.
    func formatAsToolResult(_ value: JSONValue) -> String {
        let sanitized = sanitize(value)
        if case .string(let s) = sanitized { return s }
        if let data = try? JSONEncoder().encode(sanitized),
           let str = String(data: data, encoding: .utf8) {
            return ToolResultText.clamp(str, toBytes: maxPayloadBytes)
        }
        return "{}"
    }

    /// Truncates text exceeding maxCharacters, appending ellipsis.
    static func sanitizeText(_ text: String, maxCharacters: Int = 8_000) -> String {
        guard text.count > maxCharacters else { return text }
        return String(text.prefix(maxCharacters)) + "..."
    }

    /// Recursively bounds a JSONValue to the specified maximum nesting depth.
    static func sanitizeJSON(_ value: JSONValue, maxDepth: Int = 8) -> JSONValue {
        let sanitizer = MCPResultSanitizer(maxNestingDepth: maxDepth)
        return sanitizer.sanitize(value)
    }
}
