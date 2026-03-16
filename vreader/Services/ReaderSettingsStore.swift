import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
@Observable
@MainActor
final class ReaderSettingsStore {
    static let themeKey = "readerTheme"
    static let typographyKey = "readerTypography"
    static let readingModeKey = "readerReadingMode"
    static let useCustomBackgroundKey = "readerUseCustomBackground"
    static let backgroundOpacityKey = "readerBackgroundOpacity"
    var theme: ReaderTheme { didSet { defaults.set(theme.rawValue, forKey: Self.themeKey) } }
    var readingMode: ReadingMode { didSet { defaults.set(readingMode.rawValue, forKey: Self.readingModeKey) } }
    var typography: TypographySettings {
        didSet { if let data = try? JSONEncoder().encode(typography) { defaults.set(data, forKey: Self.typographyKey) } }
    }
    var useCustomBackground: Bool { didSet { defaults.set(useCustomBackground, forKey: Self.useCustomBackgroundKey) } }
    var backgroundOpacity: Double {
        get { _backgroundOpacity }
        set { _backgroundOpacity = min(max(newValue, 0.0), 1.0); defaults.set(_backgroundOpacity, forKey: Self.backgroundOpacityKey) }
    }
    private var _backgroundOpacity: Double
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = ReaderTheme(rawValue: defaults.string(forKey: Self.themeKey) ?? "") ?? .default
        self.readingMode = ReadingMode(rawValue: defaults.string(forKey: Self.readingModeKey) ?? "") ?? .native
        if let data = defaults.data(forKey: Self.typographyKey), let d = try? JSONDecoder().decode(TypographySettings.self, from: data) { self.typography = d } else { self.typography = TypographySettings() }
        self.useCustomBackground = defaults.bool(forKey: Self.useCustomBackgroundKey)
        self._backgroundOpacity = min(max((defaults.object(forKey: Self.backgroundOpacityKey) as? Double) ?? 0.15, 0.0), 1.0)
    }
    #if canImport(UIKit)
    var uiFont: UIFont {
        let size = typography.fontSize
        switch typography.fontFamily {
        case .system: return .systemFont(ofSize: size)
        case .serif: return UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        case .monospace: return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
    var uiBackgroundColor: UIColor { theme.backgroundColor }
    var uiTextColor: UIColor { theme.textColor }
    var uiSecondaryTextColor: UIColor { theme.secondaryTextColor }
    var lineSpacingPoints: CGFloat { typography.fontSize * (typography.lineSpacing - 1.0) }
    var cjkLetterSpacing: CGFloat { typography.cjkSpacing ? typography.fontSize * 0.05 : 0 }
    #endif
    #if canImport(UIKit)
    var mdRenderConfig: MDRenderConfig { MDRenderConfig(fontSize: typography.fontSize, lineSpacing: lineSpacingPoints, textColor: uiTextColor) }
    var txtViewConfig: TXTViewConfig {
        var c = TXTViewConfig(); c.fontSize = typography.fontSize; c.lineSpacing = lineSpacingPoints
        c.textColor = uiTextColor; c.backgroundColor = uiBackgroundColor; c.letterSpacing = cjkLetterSpacing
        switch typography.fontFamily { case .system: c.fontName = nil; case .serif: c.fontName = "Georgia"
        case .monospace: c.fontName = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName }
        return c
    }
    #endif
}
