// Purpose: Reader theme enum defining background, text, and secondary text colors.
// Each theme provides WCAG AA-compliant color pairs for reading content.
//
// Key decisions:
// - Three themes: light (default), sepia (warm), dark.
// - Codable + RawRepresentable for @AppStorage compatibility.
// - Uses static UIColor instances (not dynamic/semantic) so themes are fully controlled.
// - WCAG AA: primary text >= 4.5:1, secondary text >= 3.0:1 contrast ratio.
//
// @coordinates-with: TypographySettings.swift, ReaderSettingsStore.swift

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Reader color theme.
enum ReaderTheme: String, Codable, CaseIterable, Sendable {
    case light
    case sepia
    case dark

    /// The default theme for new users.
    static var `default`: ReaderTheme { .light }

    #if canImport(UIKit)
    // MARK: - Cached Color Values

    private static let lightBg = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    private static let sepiaBg = UIColor(red: 0.96, green: 0.93, blue: 0.87, alpha: 1.0)
    private static let darkBg = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)

    private static let lightText = UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
    private static let sepiaText = UIColor(red: 0.23, green: 0.17, blue: 0.09, alpha: 1.0)
    private static let darkText = UIColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1.0)

    private static let lightSecondary = UIColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1.0)
    private static let sepiaSecondary = UIColor(red: 0.45, green: 0.38, blue: 0.28, alpha: 1.0)
    private static let darkSecondary = UIColor(red: 0.60, green: 0.60, blue: 0.62, alpha: 1.0)

    /// Background color for the reading area.
    var backgroundColor: UIColor {
        switch self {
        case .light: return Self.lightBg
        case .sepia: return Self.sepiaBg
        case .dark: return Self.darkBg
        }
    }

    /// Primary text color.
    var textColor: UIColor {
        switch self {
        case .light: return Self.lightText
        case .sepia: return Self.sepiaText
        case .dark: return Self.darkText
        }
    }

    /// Secondary/muted text color (for metadata, timestamps, etc.).
    var secondaryTextColor: UIColor {
        switch self {
        case .light: return Self.lightSecondary
        case .sepia: return Self.sepiaSecondary
        case .dark: return Self.darkSecondary
        }
    }

    /// Generates a `<style>` tag with CSS overrides for EPUB content rendering.
    /// Injected into WKWebView to apply the reader theme to XHTML content.
    func epubOverrideCSS(fontSize: CGFloat) -> String {
        let bg = cssColor(backgroundColor)
        let fg = cssColor(textColor)
        let secondary = cssColor(secondaryTextColor)
        let size = String(format: "%.1f", fontSize)
        return """
        <style id="vreader-theme">\
        html, body { background-color: \(bg) !important; color: \(fg) !important; font-size: \(size)px !important; }\
        a { color: \(secondary) !important; }\
        </style>
        """
    }

    /// Converts a UIColor to a CSS rgb() string.
    private func cssColor(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgb(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)))"
    }
    #endif
}
