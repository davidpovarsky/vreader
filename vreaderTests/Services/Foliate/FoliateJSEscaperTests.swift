// Purpose: Tests for FoliateJSEscaper — shared sanitization utility for escaping
// strings before JS/CSS interpolation in the Foliate-js reader bridge.

import Testing
@testable import vreader

@Suite("FoliateJSEscaper")
struct FoliateJSEscaperTests {

    // MARK: - escapeForJSString: Special Characters

    @Test func escapeForJSStringHandlesBackslash() {
        let result = FoliateJSEscaper.escapeForJSString("path\\to\\file")
        #expect(result == "path\\\\to\\\\file", "Backslash must be doubled")
    }

    @Test func escapeForJSStringHandlesSingleQuote() {
        let result = FoliateJSEscaper.escapeForJSString("it's")
        #expect(result == "it\\'s", "Single quote must be escaped")
    }

    @Test func escapeForJSStringHandlesNewline() {
        let result = FoliateJSEscaper.escapeForJSString("line1\nline2")
        #expect(result == "line1\\nline2", "Newline must be escaped")
    }

    @Test func escapeForJSStringHandlesCarriageReturn() {
        let result = FoliateJSEscaper.escapeForJSString("line1\rline2")
        #expect(result == "line1\\rline2", "Carriage return must be escaped")
    }

    @Test func escapeForJSStringHandlesTab() {
        let result = FoliateJSEscaper.escapeForJSString("col1\tcol2")
        #expect(result == "col1\\tcol2", "Tab must be escaped")
    }

    @Test func escapeForJSStringHandlesLineSeparatorU2028() {
        let input = "before\u{2028}after"
        let result = FoliateJSEscaper.escapeForJSString(input)
        #expect(result == "before\\u2028after", "U+2028 line separator must be escaped")
    }

    @Test func escapeForJSStringHandlesParagraphSeparatorU2029() {
        let input = "before\u{2029}after"
        let result = FoliateJSEscaper.escapeForJSString(input)
        #expect(result == "before\\u2029after", "U+2029 paragraph separator must be escaped")
    }

    @Test func escapeForJSStringPreservesNormalText() {
        let result = FoliateJSEscaper.escapeForJSString("Hello World 123")
        #expect(result == "Hello World 123", "Normal text must be unchanged")
    }

    @Test func escapeForJSStringHandlesEmptyString() {
        let result = FoliateJSEscaper.escapeForJSString("")
        #expect(result == "", "Empty string must return empty")
    }

    @Test func escapeForJSStringHandlesCombinedSpecialChars() {
        let result = FoliateJSEscaper.escapeForJSString("a\\b'c\nd\re\tf\u{2028}g\u{2029}h")
        #expect(
            result == "a\\\\b\\'c\\nd\\re\\tf\\u2028g\\u2029h",
            "All special characters must be escaped in one pass"
        )
    }

    @Test func escapeForJSStringHandlesCJKText() {
        let result = FoliateJSEscaper.escapeForJSString("你好世界")
        #expect(result == "你好世界", "CJK characters must be preserved")
    }

    @Test func escapeForJSStringHandlesEPUBCFI() {
        // Typical EPUB CFI string
        let cfi = "epubcfi(/6/4!/4/2/1:0)"
        let result = FoliateJSEscaper.escapeForJSString(cfi)
        #expect(result == cfi, "EPUB CFI without special chars must be preserved")
    }

    // MARK: - escapeForCSS: Special Characters

    @Test func escapeForCSSHandlesDoubleQuotes() {
        let result = FoliateJSEscaper.escapeForCSS("font\"name")
        #expect(!result.contains("\""), "Double quotes must be removed or escaped")
    }

    @Test func escapeForCSSHandlesSingleQuotes() {
        let result = FoliateJSEscaper.escapeForCSS("font'name")
        #expect(!result.contains("'"), "Single quotes must be removed or escaped")
    }

    @Test func escapeForCSSHandlesSemicolons() {
        let result = FoliateJSEscaper.escapeForCSS("value; color: red")
        #expect(!result.contains(";"), "Semicolons must be removed to prevent rule injection")
    }

    @Test func escapeForCSSHandlesOpenBrace() {
        let result = FoliateJSEscaper.escapeForCSS("value { color: red")
        #expect(!result.contains("{"), "Open braces must be removed")
    }

    @Test func escapeForCSSHandlesCloseBrace() {
        let result = FoliateJSEscaper.escapeForCSS("value } .x")
        #expect(!result.contains("}"), "Close braces must be removed")
    }

    @Test func escapeForCSSHandlesBackslash() {
        let result = FoliateJSEscaper.escapeForCSS("value\\escape")
        #expect(!result.contains("\\"), "Backslashes must be removed")
    }

    @Test func escapeForCSSHandlesNewlines() {
        let result = FoliateJSEscaper.escapeForCSS("value\ninjection")
        #expect(!result.contains("\n"), "Newlines must be removed")
        let result2 = FoliateJSEscaper.escapeForCSS("value\rinjection")
        #expect(!result2.contains("\r"), "Carriage returns must be removed")
    }

    @Test func escapeForCSSPreservesNormalText() {
        let result = FoliateJSEscaper.escapeForCSS("Georgia")
        #expect(result == "Georgia", "Normal font names must be preserved")
    }

    @Test func escapeForCSSPreservesCSSFunctions() {
        // rgb() and similar CSS value functions should be preserved
        let result = FoliateJSEscaper.escapeForCSS("rgb(26, 26, 26)")
        #expect(result == "rgb(26, 26, 26)", "CSS function syntax must be preserved")
    }

    @Test func escapeForCSSHandlesEmptyString() {
        let result = FoliateJSEscaper.escapeForCSS("")
        #expect(result == "", "Empty string must return empty")
    }

    // MARK: - sanitizeCSSColor

    @Test func sanitizeCSSColorReturnsNilForNil() {
        let result = FoliateJSEscaper.sanitizeCSSColor(nil)
        #expect(result == nil, "Nil input must return nil")
    }

    @Test func sanitizeCSSColorReturnsNilForEmptyString() {
        let result = FoliateJSEscaper.sanitizeCSSColor("")
        #expect(result == nil, "Empty string must return nil")
    }

    @Test func sanitizeCSSColorReturnsNilForWhitespace() {
        let result = FoliateJSEscaper.sanitizeCSSColor("   ")
        #expect(result == nil, "Whitespace-only must return nil")
    }

    @Test func sanitizeCSSColorReturnsValueForValidHex3() {
        let result = FoliateJSEscaper.sanitizeCSSColor("#fff")
        #expect(result == "#fff", "Valid 3-digit hex must be returned")
    }

    @Test func sanitizeCSSColorReturnsValueForValidHex6() {
        let result = FoliateJSEscaper.sanitizeCSSColor("#1a1a1a")
        #expect(result == "#1a1a1a", "Valid 6-digit hex must be returned")
    }

    @Test func sanitizeCSSColorReturnsValueForValidHex8() {
        let result = FoliateJSEscaper.sanitizeCSSColor("#1a1a1aff")
        #expect(result == "#1a1a1aff", "Valid 8-digit hex with alpha must be returned")
    }

    @Test func sanitizeCSSColorReturnsValueForNamedColor() {
        let result = FoliateJSEscaper.sanitizeCSSColor("red")
        #expect(result == "red", "Named CSS colors must be returned")
    }

    @Test func sanitizeCSSColorReturnsValueForRGBFunction() {
        let result = FoliateJSEscaper.sanitizeCSSColor("rgb(26, 26, 26)")
        #expect(result == "rgb(26, 26, 26)", "rgb() colors must be returned")
    }

    @Test func sanitizeCSSColorReturnsNilForInjectionAttempt() {
        let result = FoliateJSEscaper.sanitizeCSSColor("#fff; } body { display: none")
        #expect(result == nil, "Injection attempts must return nil")
    }

    @Test func sanitizeCSSColorReturnsNilForBraces() {
        let result = FoliateJSEscaper.sanitizeCSSColor("red { x")
        #expect(result == nil, "Values with braces must return nil")
    }

    // MARK: - sanitizeFlow

    @Test func sanitizeFlowReturnsPaginatedForPaginated() {
        let result = FoliateJSEscaper.sanitizeFlow("paginated")
        #expect(result == "paginated")
    }

    @Test func sanitizeFlowReturnsScrolledForScrolled() {
        let result = FoliateJSEscaper.sanitizeFlow("scrolled")
        #expect(result == "scrolled")
    }

    @Test func sanitizeFlowReturnsPaginatedForUnknownInput() {
        let result = FoliateJSEscaper.sanitizeFlow("unknown")
        #expect(result == "paginated", "Unknown flow must default to paginated")
    }

    @Test func sanitizeFlowReturnsPaginatedForEmptyString() {
        let result = FoliateJSEscaper.sanitizeFlow("")
        #expect(result == "paginated", "Empty flow must default to paginated")
    }

    @Test func sanitizeFlowReturnsPaginatedForInjectionAttempt() {
        let result = FoliateJSEscaper.sanitizeFlow("paginated', x: '")
        #expect(result == "paginated", "Injection attempt must default to paginated")
    }

    // MARK: - clampFontSize

    @Test func clampFontSizeReturnsSameForValidValue() {
        #expect(FoliateJSEscaper.clampFontSize(18) == 18)
    }

    @Test func clampFontSizeClampsBelow8() {
        #expect(FoliateJSEscaper.clampFontSize(4) == 8, "Values below 8 must clamp to 8")
    }

    @Test func clampFontSizeClampsAbove72() {
        #expect(FoliateJSEscaper.clampFontSize(100) == 72, "Values above 72 must clamp to 72")
    }

    @Test func clampFontSizeBoundary8() {
        #expect(FoliateJSEscaper.clampFontSize(8) == 8, "Boundary value 8 must be kept")
    }

    @Test func clampFontSizeBoundary72() {
        #expect(FoliateJSEscaper.clampFontSize(72) == 72, "Boundary value 72 must be kept")
    }

    // MARK: - clampLineHeight

    @Test func clampLineHeightReturnsSameForValidValue() {
        #expect(FoliateJSEscaper.clampLineHeight(1.6) == 1.6)
    }

    @Test func clampLineHeightClampsBelow0_8() {
        #expect(FoliateJSEscaper.clampLineHeight(0.5) == 0.8, "Values below 0.8 must clamp to 0.8")
    }

    @Test func clampLineHeightClampsAbove3_0() {
        #expect(FoliateJSEscaper.clampLineHeight(5.0) == 3.0, "Values above 3.0 must clamp to 3.0")
    }

    @Test func clampLineHeightBoundary0_8() {
        #expect(FoliateJSEscaper.clampLineHeight(0.8) == 0.8, "Boundary 0.8 must be kept")
    }

    @Test func clampLineHeightBoundary3_0() {
        #expect(FoliateJSEscaper.clampLineHeight(3.0) == 3.0, "Boundary 3.0 must be kept")
    }

    // MARK: - clampNonNegative

    @Test func clampNonNegativeReturnsSameForPositive() {
        #expect(FoliateJSEscaper.clampNonNegative(48) == 48)
    }

    @Test func clampNonNegativeReturnsZeroForNegative() {
        #expect(FoliateJSEscaper.clampNonNegative(-5) == 0, "Negative values must clamp to 0")
    }

    @Test func clampNonNegativeReturnsZeroForZero() {
        #expect(FoliateJSEscaper.clampNonNegative(0) == 0, "Zero must be kept as zero")
    }
}
