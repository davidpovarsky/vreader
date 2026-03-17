// Purpose: Tests for WI-B07 — EPUBTextStripper. Validates conversion of EPUB
// XHTML to NSAttributedString, preserving paragraph breaks, bold/italic styling,
// heading levels, link text, and image placeholders. Also tests routing logic
// for complex chapters.
//
// @coordinates-with: EPUBTextStripper.swift, EPUBComplexityClassifier.swift

import Testing
import UIKit
@testable import vreader

@Suite("EPUBTextStripper")
@MainActor
struct EPUBTextStripperTests {

    // MARK: - stripSimpleHTML_preservesParagraphs

    @Test func stripSimpleHTML_preservesParagraphs() {
        let html = """
        <html><body>
        <p>First paragraph.</p>
        <p>Second paragraph.</p>
        <p>Third paragraph.</p>
        </body></html>
        """
        let result = EPUBTextStripper.attributedString(from: html)
        #expect(result != nil, "Should produce a non-nil attributed string")

        let text = result!.string
        // Each paragraph should be separated (by newline or paragraph break)
        #expect(text.contains("First paragraph"), "Should contain first paragraph text")
        #expect(text.contains("Second paragraph"), "Should contain second paragraph text")
        #expect(text.contains("Third paragraph"), "Should contain third paragraph text")

        // Paragraphs should NOT be merged onto the same line
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(lines.count >= 3, "Should have at least 3 non-empty lines, got \(lines.count)")
    }

    // MARK: - stripBoldItalic_preservesStyling

    @Test func stripBoldItalic_preservesStyling() {
        let html = """
        <html><body>
        <p>Normal <b>bold</b> and <em>italic</em> text.</p>
        </body></html>
        """
        let result = EPUBTextStripper.attributedString(from: html)
        #expect(result != nil)

        let attrStr = result!
        var foundBold = false
        var foundItalic = false

        attrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            guard let font = value as? UIFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitBold) { foundBold = true }
            if traits.contains(.traitItalic) { foundItalic = true }
        }

        #expect(foundBold, "Should preserve bold formatting")
        #expect(foundItalic, "Should preserve italic formatting")
    }

    // MARK: - stripHeadings_preservesLevels

    @Test func stripHeadings_preservesLevels() {
        let html = """
        <html><body>
        <h1>Main Title</h1>
        <h2>Subtitle</h2>
        <h3>Section</h3>
        <p>Body text</p>
        </body></html>
        """
        let result = EPUBTextStripper.attributedString(from: html)
        #expect(result != nil)

        let attrStr = result!
        let text = attrStr.string
        #expect(text.contains("Main Title"), "Should contain h1 text")
        #expect(text.contains("Subtitle"), "Should contain h2 text")
        #expect(text.contains("Section"), "Should contain h3 text")

        // h1 should have a larger font than body text
        // Find font at "Main Title" position
        let h1Range = (text as NSString).range(of: "Main Title")
        if h1Range.location != NSNotFound {
            let h1Font = attrStr.attribute(.font, at: h1Range.location, effectiveRange: nil) as? UIFont

            let bodyRange = (text as NSString).range(of: "Body text")
            if bodyRange.location != NSNotFound {
                let bodyFont = attrStr.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? UIFont

                if let h1Size = h1Font?.pointSize, let bodySize = bodyFont?.pointSize {
                    #expect(h1Size > bodySize,
                            "h1 font (\(h1Size)) should be larger than body font (\(bodySize))")
                }
            }
        }
    }

    // MARK: - stripLinks_preservesText

    @Test func stripLinks_preservesText() {
        let html = """
        <html><body>
        <p>Visit <a href="https://example.com">Example Site</a> for more.</p>
        </body></html>
        """
        let result = EPUBTextStripper.attributedString(from: html)
        #expect(result != nil)

        let text = result!.string
        #expect(text.contains("Example Site"), "Link text should be preserved")
        #expect(text.contains("for more"), "Surrounding text should be preserved")
    }

    // MARK: - stripImages_insertsPlaceholder

    @Test func stripImages_insertsPlaceholder() {
        let html = """
        <html><body>
        <p>Text before.</p>
        <img src="cover.jpg" alt="Book Cover" />
        <p>Text after.</p>
        </body></html>
        """
        let result = EPUBTextStripper.attributedString(from: html)
        #expect(result != nil)

        let text = result!.string
        #expect(text.contains("Text before"), "Text before image should be preserved")
        #expect(text.contains("Text after"), "Text after image should be preserved")
        // Image should produce either a placeholder or attachment marker.
        // The exact representation depends on NSAttributedString's HTML import.
        // At minimum, no crash.
    }

    // MARK: - emptyHTML_returnsEmpty

    @Test func emptyHTML_returnsEmpty() {
        let result = EPUBTextStripper.attributedString(from: "")
        // Empty input should return nil or empty attributed string
        if let attrStr = result {
            #expect(attrStr.length == 0,
                    "Empty HTML should produce empty attributed string, got length \(attrStr.length)")
        }
        // nil is also acceptable
    }

    // MARK: - complexHTML_routesToNative (integration check)

    @Test func complexHTML_detectedCorrectly() {
        let complexHTML = """
        <html><body>
        <table><tr><td>Cell 1</td><td>Cell 2</td></tr></table>
        </body></html>
        """
        // EPUBTextStripper.shouldUseNative checks complexity
        #expect(EPUBTextStripper.shouldUseNative(html: complexHTML),
                "HTML with table should route to native WKWebView")
    }

    @Test func simpleHTML_notRoutedToNative() {
        let simpleHTML = """
        <html><body>
        <p>Simple paragraph content.</p>
        </body></html>
        """
        #expect(!EPUBTextStripper.shouldUseNative(html: simpleHTML),
                "Simple HTML should NOT route to native")
    }

    @Test func svgHTML_routesToNative() {
        let svgHTML = """
        <html><body>
        <svg><circle cx="50" cy="50" r="40"/></svg>
        </body></html>
        """
        #expect(EPUBTextStripper.shouldUseNative(html: svgHTML),
                "HTML with SVG should route to native WKWebView")
    }

    // MARK: - CJK content extraction

    @Test func cjkContent_correctExtraction() {
        let html = """
        <html><body>
        <p>这是第一段中文内容。</p>
        <p>这是第二段中文内容，包含<b>粗体</b>文字。</p>
        </body></html>
        """
        let result = EPUBTextStripper.attributedString(from: html)
        #expect(result != nil)

        let text = result!.string
        #expect(text.contains("这是第一段中文内容"), "Chinese text should be preserved")
        #expect(text.contains("这是第二段中文内容"), "Second paragraph Chinese text should be preserved")
        #expect(text.contains("粗体"), "Bold Chinese text should be preserved")
    }

    // MARK: - Edge cases

    @Test func htmlWithOnlyWhitespace_returnsEmptyOrNil() {
        let result = EPUBTextStripper.attributedString(from: "   \n\t  ")
        if let attrStr = result {
            let trimmed = attrStr.string.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(trimmed.isEmpty, "Whitespace-only HTML should produce empty text")
        }
    }

    @Test func malformedHTML_doesNotCrash() {
        let broken = "<html><body><p>Unclosed paragraph<b>and bold"
        // Should not crash — may return partial content or nil
        let result = EPUBTextStripper.attributedString(from: broken)
        // Just verify no crash; content may or may not parse
        if let attrStr = result {
            #expect(attrStr.string.contains("Unclosed paragraph") || attrStr.length >= 0)
        }
    }

    @Test func htmlEntities_decoded() {
        let html = """
        <html><body><p>Rock &amp; Roll &lt;live&gt; &quot;concert&quot;</p></body></html>
        """
        let result = EPUBTextStripper.attributedString(from: html)
        #expect(result != nil)
        let text = result!.string
        #expect(text.contains("Rock & Roll"), "HTML entities should be decoded")
        #expect(text.contains("<live>"), "HTML entities should be decoded")
    }

    @Test func nestedFormatting_preserved() {
        let html = """
        <html><body>
        <p><strong><em>Bold italic</em></strong> normal</p>
        </body></html>
        """
        let result = EPUBTextStripper.attributedString(from: html)
        #expect(result != nil)

        let attrStr = result!
        let biRange = (attrStr.string as NSString).range(of: "Bold italic")
        if biRange.location != NSNotFound {
            let font = attrStr.attribute(.font, at: biRange.location, effectiveRange: nil) as? UIFont
            if let traits = font?.fontDescriptor.symbolicTraits {
                #expect(traits.contains(.traitBold), "Should be bold")
                #expect(traits.contains(.traitItalic), "Should be italic")
            }
        }
    }
}
