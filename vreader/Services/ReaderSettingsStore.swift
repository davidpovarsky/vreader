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
    var theme: ReaderTheme { didSet { guard !suppressPersistence else { return }; defaults.set(theme.rawValue, forKey: Self.themeKey) } }
    var readingMode: ReadingMode { didSet { guard !suppressPersistence else { return }; defaults.set(readingMode.rawValue, forKey: Self.readingModeKey) } }
    var epubLayout: EPUBLayoutPreference { didSet { guard !suppressPersistence else { return }; defaults.set(epubLayout.rawValue, forKey: Self.epubLayoutKey) } }
    /// Whether auto page turning is enabled (Issue 9).
    var autoPageTurn: Bool { didSet { guard !suppressPersistence else { return }; defaults.set(autoPageTurn, forKey: Self.autoPageTurnKey) } }
    /// Page turn animation style (B11).
    var pageTurnAnimation: PageTurnAnimation {
        didSet { guard !suppressPersistence else { return }; defaults.set(pageTurnAnimation.rawValue, forKey: Self.pageTurnAnimationKey) }
    }
    /// Interval in seconds between auto page turns (Issue 9). Clamped to 1...60.
    var autoPageTurnInterval: TimeInterval {
        didSet {
            autoPageTurnInterval = max(1.0, min(60.0, autoPageTurnInterval))
            guard !suppressPersistence else { return }
            defaults.set(autoPageTurnInterval, forKey: Self.autoPageTurnIntervalKey)
        }
    }
    /// Chinese Simplified/Traditional conversion direction (E04).
    var chineseConversion: ChineseConversionDirection {
        didSet { guard !suppressPersistence else { return }; defaults.set(chineseConversion.rawValue, forKey: Self.chineseConversionKey) }
    }
    var typography: TypographySettings {
        didSet { guard !suppressPersistence else { return }; if let data = try? JSONEncoder().encode(typography) { defaults.set(data, forKey: Self.typographyKey) } }
    }
    var useCustomBackground: Bool { didSet { guard !suppressPersistence else { return }; defaults.set(useCustomBackground, forKey: Self.useCustomBackgroundKey) } }
    var backgroundOpacity: Double {
        get { _backgroundOpacity }
        set { _backgroundOpacity = min(max(newValue, 0.0), 1.0); if !suppressPersistence { defaults.set(_backgroundOpacity, forKey: Self.backgroundOpacityKey) } }
    }
    private var _backgroundOpacity: Double
    /// When true, property mutations do NOT write to UserDefaults (bug #84 audit fix).
    /// Used by `applyResolvedSettings` to avoid leaking per-book overrides into global defaults.
    private var suppressPersistence = false
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
    /// Applies resolved per-book settings onto this store instance (bug #84).
    /// Suppresses UserDefaults persistence so per-book overrides don't leak into global defaults.
    func applyResolvedSettings(_ resolved: ResolvedSettings) {
        suppressPersistence = true
        defer { suppressPersistence = false }
        if let t = ReaderTheme(rawValue: resolved.themeName), t != theme { theme = t }
        if let m = ReadingMode(rawValue: resolved.readingMode), m != readingMode { readingMode = m }
        if resolved.fontSize != typography.fontSize { typography.fontSize = resolved.fontSize }
        if resolved.lineSpacing != typography.lineSpacing { typography.lineSpacing = resolved.lineSpacing }
        if let f = ReaderFontFamily(rawValue: resolved.fontName), f != typography.fontFamily {
            typography.fontFamily = f
        }
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
