// Purpose: Converts EPUB XHTML chapter content to NSAttributedString for the
// Unified reflow engine (WI-B07). Uses Apple's built-in HTML-to-attributed-string
// converter to preserve formatting (bold, italic, headings, links, paragraphs).
//
// Key decisions:
// - NSAttributedString(data:options:[.documentType: .html]) for reliable HTML parsing.
// - Delegates complexity detection to EPUBComplexityClassifier.
// - Empty or nil input returns nil (caller handles gracefully).
// - Must run on main thread (UIKit requirement for HTML attributed string import).
//
// @coordinates-with: EPUBComplexityClassifier.swift, EPUBReaderContainerView.swift,
//   UnifiedTextRendererViewModel.swift

#if canImport(UIKit)
import UIKit

/// Converts EPUB XHTML to NSAttributedString for the Unified reflow engine.
///
/// Simple chapters (paragraphs, headings, inline formatting) are converted to
/// attributed text. Complex chapters (tables, SVG, MathML) should remain in
/// WKWebView — use `shouldUseNative(html:)` to check before converting.
enum EPUBTextStripper {

    // MARK: - Public API

    /// Converts HTML string to an NSAttributedString preserving formatting.
    ///
    /// Returns `nil` for empty input or if HTML parsing fails.
    /// Must be called on the main thread (UIKit requirement).
    ///
    /// - Parameter html: XHTML content from an EPUB chapter.
    /// - Returns: Attributed string with paragraph breaks, bold/italic, headings preserved.
    @MainActor
    static func attributedString(from html: String) -> NSAttributedString? {
        guard !html.isEmpty else { return nil }

        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = html.data(using: .utf8) else { return nil }

        do {
            let attrStr = try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            )
            guard attrStr.length > 0 else { return nil }
            return attrStr
        } catch {
            return nil
        }
    }

    /// Whether the given HTML chapter should use the native WKWebView renderer
    /// instead of the Unified engine. Delegates to EPUBComplexityClassifier.
    ///
    /// - Parameter html: XHTML content from an EPUB chapter.
    /// - Returns: `true` if the chapter contains complex layout (tables, SVG, etc.).
    static func shouldUseNative(html: String) -> Bool {
        EPUBComplexityClassifier.classify(html: html) == .complex
    }
}
#endif
