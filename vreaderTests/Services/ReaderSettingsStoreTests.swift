import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader
@Suite("ReaderSettingsStore") @MainActor struct ReaderSettingsStoreTests {
    private func makeStore() -> ReaderSettingsStore {
        ReaderSettingsStore(defaults: UserDefaults(suiteName: "RSS-\(UUID().uuidString)")!)
    }
    @Test func defaultTheme() { #expect(makeStore().theme == .light) }
    @Test func defaultTypography() { let s = makeStore(); #expect(s.typography.fontSize == 18) }
    #if canImport(UIKit)
    @Test func uiFontForSystemFamily() { #expect(makeStore().uiFont.pointSize == 18) }
    @Test func uiBackgroundColorMatchesTheme() {
        var s = makeStore(); s.theme = .dark; var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        s.uiBackgroundColor.getRed(&r, green: &g, blue: &b, alpha: &a); #expect(r < 0.2)
    }
    @Test func lineSpacingPoints() {
        var s = makeStore(); s.typography.fontSize = 20; s.typography.lineSpacing = 1.6
        #expect(abs(s.lineSpacingPoints - 12.0) < 0.01)
    }
    @Test func mdRenderConfigReflectsSettings() {
        var s = makeStore(); s.typography.fontSize = 22; s.typography.lineSpacing = 1.6
        #expect(s.mdRenderConfig.fontSize == 22)
    }
    @Test func txtViewConfigReflectsSettings() {
        var s = makeStore(); s.typography.fontSize = 24; #expect(s.txtViewConfig.fontSize == 24)
    }
    @Test func cjkLetterSpacingWhenEnabled() { var s = makeStore(); s.typography.cjkSpacing = true; #expect(s.cjkLetterSpacing > 0) }
    @Test func cjkLetterSpacingWhenDisabled() { var s = makeStore(); s.typography.cjkSpacing = false; #expect(s.cjkLetterSpacing == 0) }
    #endif
    @Test func themeChangeUpdatesColors() {
        var s = makeStore(); s.theme = .light
        #if canImport(UIKit)
        let l = s.uiBackgroundColor; s.theme = .dark; #expect(l != s.uiBackgroundColor)
        #endif
    }
    @Test func invalidThemeRawValueFallsBackToDefault() {
        let n = "RSS-c-\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!
        d.set("neon", forKey: ReaderSettingsStore.themeKey)
        #expect(ReaderSettingsStore(defaults: d).theme == .light); d.removePersistentDomain(forName: n)
    }
    @Test func settingsStore_defaultsToDisabled() { #expect(makeStore().useCustomBackground == false) }
    @Test func settingsStore_defaultBackgroundOpacity() { #expect(abs(makeStore().backgroundOpacity - 0.15) < 0.001) }
    @Test func settingsStore_persistsBackgroundEnabled() {
        let n = "RSS-bg-\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!
        var s1 = ReaderSettingsStore(defaults: d); s1.useCustomBackground = true
        #expect(ReaderSettingsStore(defaults: d).useCustomBackground == true); d.removePersistentDomain(forName: n)
    }
    @Test func settingsStore_persistsBackgroundOpacity() {
        let n = "RSS-bo-\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!
        var s1 = ReaderSettingsStore(defaults: d); s1.backgroundOpacity = 0.5
        #expect(abs(ReaderSettingsStore(defaults: d).backgroundOpacity - 0.5) < 0.001); d.removePersistentDomain(forName: n)
    }
    @Test func settingsStore_clampsBackgroundOpacity() {
        var s = makeStore(); s.backgroundOpacity = -0.5; #expect(s.backgroundOpacity >= 0.0)
        s.backgroundOpacity = 1.5; #expect(s.backgroundOpacity <= 1.0)
    }
    @Test func persistenceRoundTrip() {
        let n = "RSS-p-\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!
        var s1 = ReaderSettingsStore(defaults: d); s1.theme = .sepia; s1.typography.fontSize = 24
        let s2 = ReaderSettingsStore(defaults: d); #expect(s2.theme == .sepia); #expect(s2.typography.fontSize == 24)
        d.removePersistentDomain(forName: n)
    }
}
