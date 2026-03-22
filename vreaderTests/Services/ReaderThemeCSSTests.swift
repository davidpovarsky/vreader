// Purpose: Tests for ReaderTheme CSS generation used by the EPUB reader.

import Testing
import UIKit
@testable import vreader

@Suite("ReaderTheme - EPUB CSS")
struct ReaderThemeCSSTests {

    // MARK: - CSS Generation

    @Test func epubCSSContainsExactLightColors() {
        let css = ReaderTheme.light.epubOverrideCSS(fontSize: 18)
        // Light bg: rgb(255,255,255), text: rgb(25,25,25)
        #expect(css.contains("background-color: rgb(255,255,255)"), "Light theme must set white background")
        #expect(css.contains("color: rgb(25,25,25)"), "Light theme must set dark text color")
    }

    @Test func epubCSSContainsExactSepiaColors() {
        let css = ReaderTheme.sepia.epubOverrideCSS(fontSize: 18)
        // Sepia bg: rgb(244,237,221), text: rgb(58,43,22)
        #expect(css.contains("background-color: rgb(244,237,221)"), "Sepia theme must set warm background")
        #expect(css.contains("color: rgb(58,43,22)"), "Sepia theme must set brown text color")
    }

    @Test func epubCSSContainsExactDarkColors() {
        let css = ReaderTheme.dark.epubOverrideCSS(fontSize: 18)
        // Dark bg: rgb(28,28,30), text: rgb(234,234,237)
        #expect(css.contains("background-color: rgb(28,28,30)"), "Dark theme must set dark background")
        #expect(css.contains("color: rgb(234,234,237)"), "Dark theme must set light text color")
    }

    @Test func epubCSSSepiaHasDifferentColors() {
        let lightCSS = ReaderTheme.light.epubOverrideCSS(fontSize: 18)
        let sepiaCSS = ReaderTheme.sepia.epubOverrideCSS(fontSize: 18)
        #expect(lightCSS != sepiaCSS, "Sepia theme should produce different CSS than light")
    }

    @Test func epubCSSIncludesExactFontSize() {
        let css = ReaderTheme.light.epubOverrideCSS(fontSize: 22)
        #expect(css.contains("font-size: 22.0px"), "CSS must include the exact requested font size")
    }

    @Test func epubCSSPreservesFractionalFontSize() {
        let css = ReaderTheme.light.epubOverrideCSS(fontSize: 17.5)
        #expect(css.contains("font-size: 17.5px"), "CSS must preserve fractional font size")
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
            #expect(css.contains("color:"), "\(theme.rawValue) must set text color")
            #expect(css.contains("font-size:"), "\(theme.rawValue) must set font-size")
        }
    }

    @Test func epubCSSContainsLinkColor() {
        for theme in ReaderTheme.allCases {
            let css = theme.epubOverrideCSS(fontSize: 18)
            #expect(css.contains("a:link { color:"), "\(theme.rawValue) must style link color")
        }
    }

    // MARK: - Bug #57: EPUB font-size must override descendant text elements

    @Test func epubCSSOverridesBodyTextElements() {
        // EPUB stylesheets often set font-size on p, div, li etc.
        // Our override must force these to inherit from body so the user's
        // chosen font size actually takes effect (matching TXT behavior).
        let css = ReaderTheme.light.epubOverrideCSS(fontSize: 20)
        #expect(css.contains("font-size: inherit !important"), "CSS must force text elements to inherit body font-size")
    }

    @Test func epubCSSBodyTextOverrideCoversAllElements() {
        // Issue 10: Uses explicit element selectors + heading revert rule
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
}
