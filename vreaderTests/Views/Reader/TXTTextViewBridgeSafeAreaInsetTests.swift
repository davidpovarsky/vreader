// Purpose: Tests for `TXTTextViewBridge.combinedTextInset(base:safeAreaTop:)` —
// the bug #179 (TXT Dynamic Island clipping) helper that sums the typographic
// base padding with the SwiftUI safe-area top so the first line of text clears
// the Dynamic Island / status bar.

#if canImport(UIKit)
import Testing
import UIKit
@testable import vreader

@Suite("TXTTextViewBridge.combinedTextInset — bug #179 safe-area composition")
struct TXTTextViewBridgeSafeAreaInsetTests {

    private static let defaultBase = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

    @Test("sums positive safe-area top into base.top, preserves other edges")
    func sumsPositiveSafeAreaTop() {
        let combined = TXTTextViewBridge.combinedTextInset(
            base: Self.defaultBase,
            safeAreaTop: 59 // iPhone 17 Pro Dynamic Island
        )
        #expect(combined.top == 75) // 16 + 59
        #expect(combined.left == 16)
        #expect(combined.bottom == 16)
        #expect(combined.right == 16)
    }

    @Test("zero safe-area top preserves base inset (devices without DI)")
    func zeroSafeAreaPreservesBase() {
        let combined = TXTTextViewBridge.combinedTextInset(
            base: Self.defaultBase,
            safeAreaTop: 0
        )
        #expect(combined == Self.defaultBase)
    }

    @Test("negative safe-area top is clamped to 0 (defensive)")
    func negativeSafeAreaClamps() {
        let combined = TXTTextViewBridge.combinedTextInset(
            base: Self.defaultBase,
            safeAreaTop: -10
        )
        #expect(combined.top == 16) // base.top + 0, not base.top - 10
    }

    @Test("custom base inset preserved on non-top edges with safe-area added")
    func customBasePreservedWithSafeArea() {
        let custom = UIEdgeInsets(top: 24, left: 32, bottom: 8, right: 32)
        let combined = TXTTextViewBridge.combinedTextInset(
            base: custom,
            safeAreaTop: 47 // iPhone 14 (not Pro) status-bar height
        )
        #expect(combined.top == 71)
        #expect(combined.left == 32)
        #expect(combined.bottom == 8)
        #expect(combined.right == 32)
    }
}

#endif
