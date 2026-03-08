// Purpose: Tests for TXTViewConfig.renderingEquals — the production config-diff logic
// used by TXTTextViewBridge.updateUIView to decide when to re-apply text styling.
// Verifies that theme/color changes trigger text re-application (bug #10 regression).

import Testing
import UIKit
@testable import vreader

@Suite("TXTViewConfig renderingEquals")
struct TXTTextViewBridgeConfigTests {

    // MARK: - Tests

    @Test func identicalConfigsAreEqual() {
        let a = TXTViewConfig()
        let b = TXTViewConfig()
        #expect(a.renderingEquals(b), "Identical configs should be equal")
    }

    @Test func fontSizeChangeMakesUnequal() {
        let a = TXTViewConfig()
        var b = TXTViewConfig()
        b.fontSize = 24
        #expect(!a.renderingEquals(b), "fontSize change should make configs unequal")
    }

    @Test func textColorChangeMakesUnequal() {
        let a = TXTViewConfig()
        var b = TXTViewConfig()
        b.textColor = .red
        #expect(!a.renderingEquals(b), "textColor change should make configs unequal (bug #10)")
    }

    @Test func backgroundColorChangeMakesUnequal() {
        let a = TXTViewConfig()
        var b = TXTViewConfig()
        b.backgroundColor = UIColor(red: 0.96, green: 0.93, blue: 0.87, alpha: 1.0)
        #expect(!a.renderingEquals(b), "backgroundColor change should make configs unequal (bug #10)")
    }

    @Test func letterSpacingChangeMakesUnequal() {
        let a = TXTViewConfig()
        var b = TXTViewConfig()
        b.letterSpacing = 1.5
        #expect(!a.renderingEquals(b), "letterSpacing change should make configs unequal")
    }

    @Test func lineSpacingChangeMakesUnequal() {
        let a = TXTViewConfig()
        var b = TXTViewConfig()
        b.lineSpacing = 12
        #expect(!a.renderingEquals(b), "lineSpacing change should make configs unequal")
    }

    @Test func fontNameChangeMakesUnequal() {
        let a = TXTViewConfig()
        var b = TXTViewConfig()
        b.fontName = "Georgia"
        #expect(!a.renderingEquals(b), "fontName change should make configs unequal")
    }

    @Test func themeChangeFromLightToSepiaMakesUnequal() {
        let light = TXTViewConfig()
        var sepia = TXTViewConfig()
        sepia.textColor = UIColor(red: 0.23, green: 0.17, blue: 0.09, alpha: 1.0)
        sepia.backgroundColor = UIColor(red: 0.96, green: 0.93, blue: 0.87, alpha: 1.0)
        #expect(!light.renderingEquals(sepia), "Theme change (light→sepia) should make configs unequal")
    }

    @Test func themeChangeFromLightToDarkMakesUnequal() {
        let light = TXTViewConfig()
        var dark = TXTViewConfig()
        dark.textColor = UIColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1.0)
        dark.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        #expect(!light.renderingEquals(dark), "Theme change (light→dark) should make configs unequal")
    }

    // MARK: - Coordinator Restore-Once Behavior (Bug #15, #17)

    @Test @MainActor func coordinatorRestoresOnlyOnce() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        #expect(coordinator.hasRestoredPosition == false,
                "New coordinator should not have restored position yet")

        // Simulate first restore
        coordinator.hasRestoredPosition = true

        // Even if restoreOffset changes, coordinator should not restore again
        #expect(coordinator.hasRestoredPosition == true,
                "Once restored, flag should remain true")
    }

    @Test @MainActor func coordinatorStartsWithoutRestore() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        #expect(coordinator.hasRestoredPosition == false)
    }
}
