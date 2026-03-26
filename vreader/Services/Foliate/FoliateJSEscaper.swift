// Purpose: Shared sanitization utility for escaping strings before JS/CSS
// interpolation in the Foliate-js reader bridge. Prevents injection attacks
// when constructing JavaScript or CSS strings from user-controlled values.
//
// Key decisions:
// - Enum (no instances) — all methods are static pure functions.
// - escapeForJSString covers all characters that break JS single-quoted strings,
//   including U+2028/U+2029 (ECMAScript line terminators).
// - escapeForCSS strips characters that could inject new rules or break out of values.
// - sanitizeCSSColor validates structure (no braces/semicolons) before allowing through.
// - sanitizeFlow is an allowlist — only "paginated" and "scrolled" are accepted.
// - Clamping helpers enforce reasonable numeric ranges for CSS values.
//
// @coordinates-with: FoliateHighlightRenderer.swift, FoliateStyleMapper.swift,
//   FoliateViewCoordinator.swift, FoliateViewBridge.swift

import Foundation

/// Shared sanitization utility for safe JS/CSS string interpolation.
enum FoliateJSEscaper {

    // MARK: - JavaScript String Escaping

    /// Escape a string for embedding inside a JS single-quoted string literal.
    ///
    /// Handles: backslash, single quote, newline, carriage return, tab,
    /// line separator (U+2028), paragraph separator (U+2029).
    ///
    /// - Parameter value: The raw string to escape.
    /// - Returns: The escaped string safe for `'...'` interpolation.
    static func escapeForJSString(_ value: String) -> String {
        var result = value
        // Backslash must be first to avoid double-escaping.
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "'", with: "\\'")
        result = result.replacingOccurrences(of: "\n", with: "\\n")
        result = result.replacingOccurrences(of: "\r", with: "\\r")
        result = result.replacingOccurrences(of: "\t", with: "\\t")
        result = result.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        result = result.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return result
    }

    // MARK: - CSS Value Escaping

    /// Escape a string for embedding in a CSS property value.
    ///
    /// Strips characters that could inject new rules or break out of values:
    /// quotes, backslash, semicolons, braces, newlines.
    ///
    /// - Parameter value: The raw string to sanitize.
    /// - Returns: The sanitized string safe for CSS value interpolation.
    static func escapeForCSS(_ value: String) -> String {
        var result = value
        for char in ["\"", "'", "\\", ";", "{", "}", "\n", "\r"] {
            result = result.replacingOccurrences(of: char, with: "")
        }
        return result
    }

    // MARK: - CSS Color Validation

    /// Validate and sanitize a CSS color value.
    ///
    /// Returns nil for nil, empty, whitespace-only, or values containing
    /// injection characters (semicolons, braces).
    ///
    /// - Parameter value: The raw color string, or nil.
    /// - Returns: The validated color string, or nil if invalid/empty.
    static func sanitizeCSSColor(_ value: String?) -> String? {
        guard let color = value?.trimmingCharacters(in: .whitespaces),
              !color.isEmpty else {
            return nil
        }
        // Reject values with injection characters.
        let forbidden: [Character] = [";", "{", "}", "\\", "\"", "'"]
        for char in forbidden {
            if color.contains(char) { return nil }
        }
        return color
    }

    // MARK: - Flow Validation

    /// Validate a layout flow value.
    ///
    /// Only "paginated" and "scrolled" are valid. All other values
    /// (including empty strings and injection attempts) default to "paginated".
    ///
    /// - Parameter value: The raw flow string.
    /// - Returns: "paginated" or "scrolled".
    static func sanitizeFlow(_ value: String) -> String {
        switch value {
        case "paginated", "scrolled": return value
        default: return "paginated"
        }
    }

    // MARK: - Numeric Clamping

    /// Clamp a font size to a reasonable range (8-72px).
    ///
    /// - Parameter value: The raw font size.
    /// - Returns: The clamped value.
    static func clampFontSize(_ value: Int) -> Int {
        min(max(value, 8), 72)
    }

    /// Clamp a line height multiplier to a reasonable range (0.8-3.0).
    ///
    /// - Parameter value: The raw line height.
    /// - Returns: The clamped value.
    static func clampLineHeight(_ value: Double) -> Double {
        min(max(value, 0.8), 3.0)
    }

    /// Clamp an integer to non-negative (minimum 0).
    ///
    /// Use for margin, maxInlineSize, maxColumnCount.
    ///
    /// - Parameter value: The raw integer.
    /// - Returns: The clamped value (0 or greater).
    static func clampNonNegative(_ value: Int) -> Int {
        max(value, 0)
    }
}
