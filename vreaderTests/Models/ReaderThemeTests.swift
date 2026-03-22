// Purpose: Tests for ReaderTheme — color values, Codable round-trip, all cases.

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

@Suite("ReaderTheme")
struct ReaderThemeTests {

    // MARK: - All Cases

    @Test func allCasesContainsThreeThemes() {
        #expect(ReaderTheme.allCases.count == 3)
        #expect(ReaderTheme.allCases.contains(.light))
        #expect(ReaderTheme.allCases.contains(.sepia))
        #expect(ReaderTheme.allCases.contains(.dark))
    }

    // MARK: - Raw Values

    @Test func rawValueRoundTrip() {
        for theme in ReaderTheme.allCases {
            let raw = theme.rawValue
            let restored = ReaderTheme(rawValue: raw)
            #expect(restored == theme)
        }
    }

    @Test func invalidRawValueReturnsNil() {
        #expect(ReaderTheme(rawValue: "blue") == nil)
        #expect(ReaderTheme(rawValue: "") == nil)
        #expect(ReaderTheme(rawValue: "LIGHT") == nil)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        for theme in ReaderTheme.allCases {
            let data = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(ReaderTheme.self, from: data)
            #expect(decoded == theme)
        }
    }

    // MARK: - Color Values

    #if canImport(UIKit)
    @Test func lightThemeHasWhiteBackground() {
        let theme = ReaderTheme.light
        let bg = theme.backgroundColor
        // Light theme background should be white or near-white
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(bg.getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(r > 0.9)
        #expect(g > 0.9)
        #expect(b > 0.9)
    }

    @Test func lightThemeHasDarkText() {
        let theme = ReaderTheme.light
        let text = theme.textColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(text.getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(r < 0.2)
        #expect(g < 0.2)
        #expect(b < 0.2)
    }

    @Test func sepiaThemeHasWarmBackground() {
        let theme = ReaderTheme.sepia
        let bg = theme.backgroundColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(bg.getRed(&r, green: &g, blue: &b, alpha: &a))
        // Sepia should be warm-toned: red > blue
        #expect(r > b)
        #expect(r > 0.8)
    }

    @Test func darkThemeHasDarkBackground() {
        let theme = ReaderTheme.dark
        let bg = theme.backgroundColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(bg.getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(r < 0.2)
        #expect(g < 0.2)
        #expect(b < 0.2)
    }

    @Test func darkThemeHasLightText() {
        let theme = ReaderTheme.dark
        let text = theme.textColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(text.getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(r > 0.8)
        #expect(g > 0.8)
        #expect(b > 0.8)
    }

    @Test func allThemesHaveSecondaryTextColor() {
        for theme in ReaderTheme.allCases {
            let secondary = theme.secondaryTextColor
            // Secondary text should exist and be non-nil
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #expect(secondary.getRed(&r, green: &g, blue: &b, alpha: &a))
            #expect(a > 0)
        }
    }
    #endif

    // MARK: - Default

    @Test func defaultThemeIsLight() {
        #expect(ReaderTheme.default == .light)
    }

    // MARK: - EPUB CSS Generation

    #if canImport(UIKit)
    @Test func epubCSSIncludesExactFontSize() {
        let css = ReaderTheme.light.epubOverrideCSS(fontSize: 22)
        #expect(css.contains("font-size: 22.0px"), "CSS must include the exact requested font size")
    }

    @Test func epubCSSIsValidStyleTag() {
        let css = ReaderTheme.light.epubOverrideCSS(fontSize: 18)
        #expect(css.contains("<style id=\"vreader-theme\">"), "CSS should have an id'd style tag")
        #expect(css.hasSuffix("</style>"), "CSS should end with </style>")
    }

    @Test func epubCSSAllThemesProduceNonEmpty() {
        for theme in ReaderTheme.allCases {
            let css = theme.epubOverrideCSS(fontSize: 18)
            #expect(!css.isEmpty, "\(theme.rawValue) theme should produce non-empty CSS")
            #expect(css.contains("background-color:"), "\(theme.rawValue) must set background-color")
            #expect(css.contains("font-size:"), "\(theme.rawValue) must set font-size")
        }
    }

    @Test func epubCSSContainsLinkColor() {
        for theme in ReaderTheme.allCases {
            let css = theme.epubOverrideCSS(fontSize: 18)
            #expect(css.contains("a:link { color:"), "\(theme.rawValue) must style link color")
        }
    }

    // Bug #57: EPUB font-size must override descendant text elements

    @Test func epubCSSOverridesBodyTextElements() {
        // EPUB stylesheets often set font-size on p, div, li etc.
        // Our override must force these to inherit from body so the user's
        // chosen font size actually takes effect (matching TXT behavior).
        let css = ReaderTheme.light.epubOverrideCSS(fontSize: 20)
        #expect(css.contains("font-size: inherit !important"), "CSS must force text elements to inherit body font-size")
    }

    @Test func epubCSSBodyTextOverrideCoversAllElements() {
        // Issue 10: The override uses explicit element selectors to force
        // font-size inheritance. Headings get a revert rule to keep relative sizing.
        let css = ReaderTheme.light.epubOverrideCSS(fontSize: 18)
        #expect(css.contains("p, div, span, li"), "CSS must cover common text elements for font-size inheritance")
        #expect(css.contains("h1,h2,h3,h4,h5,h6"), "CSS must have heading revert rule")
        #expect(css.contains("revert"), "Headings must use 'revert' to preserve relative sizing")
    }

    @Test func epubCSSBodyTextOverrideAllThemes() {
        for theme in ReaderTheme.allCases {
            let css = theme.epubOverrideCSS(fontSize: 18)
            #expect(css.contains("font-size: inherit !important"), "\(theme.rawValue) must override descendant text elements")
        }
    }
    #endif
}
