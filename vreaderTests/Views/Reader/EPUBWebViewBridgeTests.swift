// Purpose: Tests for EPUBWebViewBridge scroll-to-fraction JS generation.
// Verifies the JavaScript string produced by scrollToFractionJS is well-formed
// and handles edge cases (0, 1, negative, NaN).
//
// @coordinates-with: EPUBWebViewBridge.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("EPUBWebViewBridge - scrollToFractionJS")
struct EPUBWebViewBridgeScrollJSTests {

    @Test("generates JS that scrolls to given fraction")
    func scrollToFractionGeneratesValidJS() {
        let js = EPUBWebViewBridge.scrollToFractionJS(0.5)
        #expect(js.contains("scrollTo"))
        #expect(js.contains("0.5"))
    }

    @Test("fraction 0 scrolls to top")
    func scrollToFractionZero() {
        let js = EPUBWebViewBridge.scrollToFractionJS(0.0)
        #expect(js.contains("scrollTo"))
        #expect(js.contains("0.0"))
    }

    @Test("fraction 1 scrolls to bottom")
    func scrollToFractionOne() {
        let js = EPUBWebViewBridge.scrollToFractionJS(1.0)
        #expect(js.contains("scrollTo"))
        #expect(js.contains("1.0"))
    }

    @Test("fraction 0.75 generates correct value")
    func scrollToFractionThreeQuarters() {
        let js = EPUBWebViewBridge.scrollToFractionJS(0.75)
        #expect(js.contains("0.75"))
    }

    @Test("negative fraction clamps to 0")
    func scrollToFractionNegativeClamps() {
        let js = EPUBWebViewBridge.scrollToFractionJS(-0.5)
        #expect(!js.contains("-0.5"))
        #expect(js.contains("0.0"))
    }

    @Test("fraction > 1 clamps to 1")
    func scrollToFractionOverOneClamps() {
        let js = EPUBWebViewBridge.scrollToFractionJS(1.5)
        #expect(!js.contains("1.5"))
        #expect(js.contains("1.0"))
    }

    @Test("NaN fraction clamps to 0")
    func scrollToFractionNaN() {
        let js = EPUBWebViewBridge.scrollToFractionJS(.nan)
        #expect(!js.contains("nan"))
        #expect(js.contains("0.0"))
    }
}
#endif
