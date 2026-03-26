// Purpose: Pure functions that generate CSS and JavaScript strings for
// the Foliate-js reader engine's setStyles() and setLayout() APIs.
// Maps VReader reader settings to Foliate-js configuration.
//
// Key decisions:
// - Enum with static methods (no instances needed for pure functions).
// - All CSS rules use !important to override book-embedded styles.
// - Optional parameters (fontFamily, colors) are omitted from output when nil/empty.
// - layoutJS generates a complete readerAPI.setLayout() call string.
// - All values are sanitized via FoliateJSEscaper before interpolation.
// - Numeric values are clamped to safe ranges.
//
// @coordinates-with: ReaderSettingsStore.swift, ReaderTheme.swift, FoliateViewBridge.swift,
//   FoliateJSEscaper.swift

import Foundation

/// Generates CSS and JavaScript configuration strings for Foliate-js.
enum FoliateStyleMapper {

    /// Generate CSS string for Foliate-js setStyles() from reader settings.
    ///
    /// - Parameters:
    ///   - fontSize: Font size in points (will be emitted as px).
    ///   - lineHeight: Line height multiplier (e.g. 1.6).
    ///   - fontFamily: Optional font family name. Omitted from CSS when nil or empty.
    ///   - textColor: Optional CSS color string (e.g. "#1a1a1a"). Omitted when nil.
    ///   - backgroundColor: Optional CSS color string (e.g. "#ffffff"). Omitted when nil.
    /// - Returns: A CSS string suitable for Foliate-js setStyles().
    static func themeCSS(
        fontSize: Int,
        lineHeight: Double,
        fontFamily: String?,
        textColor: String?,
        backgroundColor: String?
    ) -> String {
        let clampedSize = FoliateJSEscaper.clampFontSize(fontSize)
        let clampedHeight = FoliateJSEscaper.clampLineHeight(lineHeight)
        var rules: [String] = []

        // Font size and line height are always included.
        rules.append("body { font-size: \(clampedSize)px !important; line-height: \(formatLineHeight(clampedHeight)) !important; }")

        // Font family only when provided and non-empty; sanitized for CSS.
        if let family = fontFamily, !family.isEmpty {
            let safeFamily = FoliateJSEscaper.escapeForCSS(family)
            rules.append("body { font-family: \"\(safeFamily)\" !important; }")
        }

        // Text color — omitted when nil or empty.
        if let color = FoliateJSEscaper.sanitizeCSSColor(textColor) {
            rules.append("body { color: \(color) !important; }")
        }

        // Background color — omitted when nil or empty.
        if let bg = FoliateJSEscaper.sanitizeCSSColor(backgroundColor) {
            rules.append("body { background: \(bg) !important; }")
        }

        return rules.joined(separator: "\n")
    }

    /// Generate a JavaScript call string for Foliate-js setLayout().
    ///
    /// - Parameters:
    ///   - flow: Layout flow mode — "paginated" or "scrolled".
    ///   - margin: Margin in pixels.
    ///   - maxInlineSize: Maximum content width in pixels.
    ///   - maxColumnCount: Number of columns (1 or 2).
    /// - Returns: A JavaScript string calling `readerAPI.setLayout({...})`.
    static func layoutJS(
        flow: String,
        margin: Int,
        maxInlineSize: Int,
        maxColumnCount: Int
    ) -> String {
        let safeFlow = FoliateJSEscaper.sanitizeFlow(flow)
        let safeMargin = FoliateJSEscaper.clampNonNegative(margin)
        let safeInlineSize = FoliateJSEscaper.clampNonNegative(maxInlineSize)
        let safeColumnCount = min(max(maxColumnCount, 1), 2)
        return "readerAPI.setLayout({flow: '\(safeFlow)', margin: \(safeMargin), maxInlineSize: \(safeInlineSize), maxColumnCount: \(safeColumnCount)})"
    }

    // MARK: - Private

    /// Format line height to one decimal place for consistent CSS output.
    private static func formatLineHeight(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
