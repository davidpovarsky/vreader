// Purpose: Classifies EPUB chapter HTML as simple or complex to route
// chapters to the appropriate rendering engine. Simple content goes to
// the Unified reflow engine; complex content falls back to WKWebView.
//
// Key decisions:
// - Conservative: if uncertain, classify as complex (safer fallback).
// - String-based detection for speed — no full HTML/DOM parsing.
// - Per-chapter classification with book-level rollup.
//
// @coordinates-with: FormatCapabilities.swift — isComplexEPUB parameter

import Foundation

/// Whether an EPUB chapter (or entire book) is simple enough for
/// the Unified reflow engine or requires the Native WKWebView renderer.
enum EPUBComplexity: Sendable, Equatable {
    case simple
    case complex
}

/// Classifies EPUB HTML content by scanning for complex layout indicators.
///
/// Detection strategy (conservative — anything uncertain is complex):
/// - **Complex tags**: `<table`, `<math`, `<svg`, `<iframe`, `<canvas`,
///   `<video`, `<audio`
/// - **Complex CSS**: `display:grid`, `display:table`, `position:fixed`,
///   `position:absolute`
/// - **Fixed layout**: viewport meta with fixed dimensions
/// - **Simple tags** (not complex): `<p>`, `<div>`, `<span>`, `<a>`,
///   `<em>`, `<strong>`, `<h1-h6>`, `<ul>`, `<ol>`, `<li>`, `<br>`,
///   `<img>`, `<blockquote>`, `<pre>`, `<code>`
enum EPUBComplexityClassifier {

    // MARK: - Pre-compiled Patterns

    /// All complexity indicator patterns, compiled once at load time.
    /// Includes HTML tag patterns, CSS property patterns, and viewport detection.
    private static let complexityPatterns: [NSRegularExpression] = {
        let tagNames = ["table", "math", "svg", "iframe", "canvas", "video", "audio"]
        let tagPatterns = tagNames.map { "<\($0)[\\s/>]" }

        let cssPatterns = [
            "display\\s*:\\s*grid",
            "display\\s*:\\s*table",
            "position\\s*:\\s*fixed",
            "position\\s*:\\s*absolute",
        ]

        let viewportPattern = "<meta[^>]+name\\s*=\\s*[\"']viewport[\"'][^>]+width\\s*="

        let allPatterns = tagPatterns + cssPatterns + [viewportPattern]
        return allPatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: .caseInsensitive)
        }
    }()

    // MARK: - Public API

    /// Classify a single EPUB chapter's HTML content.
    ///
    /// Scans the HTML string for complex indicators (tags like `<table>`,
    /// `<svg>`, `<math>`; CSS like `display:grid`, `position:fixed`;
    /// and viewport meta with fixed dimensions).
    /// If any complex indicator is found, returns `.complex`.
    /// Empty or simple content returns `.simple`.
    static func classify(html: String) -> EPUBComplexity {
        guard !html.isEmpty else { return .simple }

        let lowered = html.lowercased()
        let range = NSRange(lowered.startIndex..., in: lowered)

        for regex in complexityPatterns {
            if regex.firstMatch(in: lowered, range: range) != nil {
                return .complex
            }
        }

        return .simple
    }

    /// Classify an entire book. If ANY chapter is complex, the book is complex.
    ///
    /// - Parameter chapterHTMLs: HTML content of each chapter in the book.
    /// - Returns: `.complex` if any chapter is complex, `.simple` otherwise.
    static func classifyBook(chapterHTMLs: [String]) -> EPUBComplexity {
        for chapter in chapterHTMLs {
            if classify(html: chapter) == .complex {
                return .complex
            }
        }
        return .simple
    }
}
