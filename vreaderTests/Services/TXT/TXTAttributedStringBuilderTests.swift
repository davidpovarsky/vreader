// Purpose: Tests for TXTAttributedStringBuilder — verifies attributed string
// construction from text + config matches expected attributes.
//
// @coordinates-with: TXTAttributedStringBuilder.swift

#if canImport(UIKit)
import Testing
import UIKit
@testable import vreader

@Suite("TXTAttributedStringBuilder")
struct TXTAttributedStringBuilderTests {

    @Test func buildWithDefaultConfig() {
        let config = TXTViewConfig()
        let text = "Hello world"
        let result = TXTAttributedStringBuilder.build(text: text, config: config)

        #expect(result.string == text)
        #expect(result.length == (text as NSString).length)
    }

    @Test func buildAppliesFont() {
        var config = TXTViewConfig()
        config.fontSize = 24
        config.fontName = nil // system font

        let result = TXTAttributedStringBuilder.build(text: "Test", config: config)
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font != nil)
        // Scaled font should be based on 24pt
        #expect(font!.pointSize >= 24)
    }

    @Test func buildAppliesCustomFontName() {
        var config = TXTViewConfig()
        config.fontSize = 18
        config.fontName = "Georgia"

        let result = TXTAttributedStringBuilder.build(text: "Test", config: config)
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font != nil)
        // Georgia is available on iOS; if it were missing, builder falls back to system font
        let isGeorgiaOrFallback = font!.fontName.contains("Georgia")
            || font!.familyName == UIFont.systemFont(ofSize: 18).familyName
        #expect(isGeorgiaOrFallback, "Font should be Georgia or system fallback")
    }

    @Test func buildAppliesTextColor() {
        var config = TXTViewConfig()
        config.textColor = .red

        let result = TXTAttributedStringBuilder.build(text: "Test", config: config)
        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        #expect(color == .red)
    }

    @Test func buildAppliesLetterSpacing() {
        var config = TXTViewConfig()
        config.letterSpacing = 2.0

        let result = TXTAttributedStringBuilder.build(text: "Test", config: config)
        let kern = result.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat
        #expect(kern == 2.0)
    }

    @Test func buildOmitsKernWhenZero() {
        var config = TXTViewConfig()
        config.letterSpacing = 0

        let result = TXTAttributedStringBuilder.build(text: "Test", config: config)
        let kern = result.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat
        #expect(kern == nil)
    }

    @Test func buildAppliesLineSpacing() {
        var config = TXTViewConfig()
        config.lineSpacing = 10

        let result = TXTAttributedStringBuilder.build(text: "Test", config: config)
        let style = result.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style != nil)
        #expect(style!.lineSpacing == 10)
    }

    @Test func buildHandlesEmptyString() {
        let config = TXTViewConfig()
        let result = TXTAttributedStringBuilder.build(text: "", config: config)
        #expect(result.string == "")
        #expect(result.length == 0)
    }

    @Test func buildHandlesLargeText() {
        let config = TXTViewConfig()
        let largeText = String(repeating: "A", count: 100_000)
        let result = TXTAttributedStringBuilder.build(text: largeText, config: config)
        #expect(result.length == 100_000)
    }

    @Test func buildHandlesCJKText() {
        var config = TXTViewConfig()
        config.letterSpacing = 0.05

        let cjk = "你好世界"
        let result = TXTAttributedStringBuilder.build(text: cjk, config: config)
        #expect(result.string == cjk)
        let kern = result.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat
        #expect(kern == 0.05)
    }
}
#endif
