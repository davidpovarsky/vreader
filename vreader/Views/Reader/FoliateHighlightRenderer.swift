// Purpose: Generates JavaScript strings for Foliate-js SVG overlay annotation
// operations (add, remove, restore). Pure string generation — no WKWebView dependency.
//
// Key decisions:
// - Static methods for pure JS string generation (no mutable state).
// - Uses readerAPI.addAnnotation / deleteAnnotation from Foliate-js bridge protocol.
// - CFI values are escaped via FoliateJSEscaper for safe embedding in JS string literals.
// - Color mapping translates VReader color names to Foliate-js color strings.
//
// @coordinates-with: FoliateReaderContainerView.swift, FoliateViewCoordinator.swift,
//   FoliateJSEscaper.swift

import Foundation

struct FoliateHighlightRenderer {

    private static let knownColors: Set<String> = ["yellow", "blue", "green", "pink"]

    /// Generates JS to add a highlight annotation in Foliate-js.
    /// - Parameters:
    ///   - cfi: The EPUB CFI string identifying the text range.
    ///   - color: The VReader highlight color name (e.g., "yellow", "blue").
    /// - Returns: A JavaScript string calling `readerAPI.addAnnotation`.
    static func addAnnotationJS(cfi: String, color: String) -> String {
        let safeCFI = FoliateJSEscaper.escapeForJSString(cfi)
        let normalizedColor = foliateColor(from: color)
        let safeColor = FoliateJSEscaper.escapeForJSString(normalizedColor)
        return "readerAPI.addAnnotation({value: '\(safeCFI)', color: '\(safeColor)'})"
    }

    /// Generates JS to remove a highlight annotation.
    /// - Parameter cfi: The EPUB CFI string identifying the annotation to remove.
    /// - Returns: A JavaScript string calling `readerAPI.deleteAnnotation`.
    static func removeAnnotationJS(cfi: String) -> String {
        let safeCFI = FoliateJSEscaper.escapeForJSString(cfi)
        return "readerAPI.deleteAnnotation({value: '\(safeCFI)'})"
    }

    /// Generates JS to restore multiple highlights at once.
    /// - Parameter highlights: Array of (cfi, color) tuples to restore.
    /// - Returns: A JavaScript string with multiple `readerAPI.addAnnotation` calls,
    ///   or an empty string if the array is empty.
    static func restoreAllJS(highlights: [(cfi: String, color: String)]) -> String {
        if highlights.isEmpty { return "" }
        return highlights
            .map { addAnnotationJS(cfi: $0.cfi, color: $0.color) }
            .joined(separator: "\n")
    }

    /// Maps a VReader highlight color name to the corresponding Foliate-js color string.
    /// - Parameter vreaderColor: The VReader color name (e.g., "yellow", "blue").
    /// - Returns: The Foliate-js color string. Defaults to "yellow" for unknown colors.
    static func foliateColor(from vreaderColor: String) -> String {
        knownColors.contains(vreaderColor) ? vreaderColor : "yellow"
    }
}
