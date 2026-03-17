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
    static let epubLayoutKey = "readerEPUBLayout"
    static let autoPageTurnKey = "readerAutoPageTurn"
    static let autoPageTurnIntervalKey = "readerAutoPageTurnInterval"
    static let pageTurnAnimationKey = "readerPageTurnAnimation"
    static let chineseConversionKey = "readerChineseConversion"
    var theme: ReaderTheme { didSet { defaults.set(theme.rawValue, forKey: Self.themeKey) } }
    var readingMode: ReadingMode { didSet { defaults.set(readingMode.rawValue, forKey: Self.readingModeKey) } }
    var epubLayout: EPUBLayoutPreference { didSet { defaults.set(epubLayout.rawValue, forKey: Self.epubLayoutKey) } }
    /// Whether auto page turning is enabled (Issue 9).
    var autoPageTurn: Bool { didSet { defaults.set(autoPageTurn, forKey: Self.autoPageTurnKey) } }
    /// Page turn animation style (B11).
    var pageTurnAnimation: PageTurnAnimation {
        didSet { defaults.set(pageTurnAnimation.rawValue, forKey: Self.pageTurnAnimationKey) }
    }
    /// Interval in seconds between auto page turns (Issue 9). Clamped to 1...60.
    var autoPageTurnInterval: TimeInterval {
        didSet {
            autoPageTurnInterval = max(1.0, min(60.0, autoPageTurnInterval))
            defaults.set(autoPageTurnInterval, forKey: Self.autoPageTurnIntervalKey)
        }
    }
    /// Chinese Simplified/Traditional conversion direction (E04).
    var chineseConversion: ChineseConversionDirection {
        didSet { defaults.set(chineseConversion.rawValue, forKey: Self.chineseConversionKey) }
    }
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
        self.epubLayout = EPUBLayoutPreference(rawValue: defaults.string(forKey: Self.epubLayoutKey) ?? "") ?? .scroll
        self.pageTurnAnimation = PageTurnAnimation(rawValue: defaults.string(forKey: Self.pageTurnAnimationKey) ?? "") ?? .none
        self.chineseConversion = ChineseConversionDirection(rawValue: defaults.string(forKey: Self.chineseConversionKey) ?? "") ?? .none
        self.autoPageTurn = defaults.bool(forKey: Self.autoPageTurnKey)
        let storedInterval = defaults.double(forKey: Self.autoPageTurnIntervalKey)
        self.autoPageTurnInterval = storedInterval > 0 ? max(1.0, min(60.0, storedInterval)) : 5.0
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
