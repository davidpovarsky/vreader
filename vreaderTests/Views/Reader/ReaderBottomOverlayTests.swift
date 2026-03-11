// Purpose: Tests for ReaderBottomOverlay extracted in WI-005.
// Validates progress formatting and display logic.
//
// @coordinates-with ReaderBottomOverlay.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReaderBottomOverlay")
struct ReaderBottomOverlayTests {

    @Test func progressPercentageFormats100Percent() {
        let formatted = ReaderBottomOverlay.formatProgress(1.0)
        #expect(formatted == "100%")
    }

    @Test func progressPercentageFormatsZeroPercent() {
        let formatted = ReaderBottomOverlay.formatProgress(0.0)
        #expect(formatted == "0%")
    }

    @Test func progressPercentageFormatsMidValue() {
        let formatted = ReaderBottomOverlay.formatProgress(0.42)
        #expect(formatted == "42%")
    }

    @Test func progressPercentageTruncatesDecimals() {
        let formatted = ReaderBottomOverlay.formatProgress(0.999)
        #expect(formatted == "99%")
    }

    @Test func progressPercentageFormatsSmallValue() {
        let formatted = ReaderBottomOverlay.formatProgress(0.01)
        #expect(formatted == "1%")
    }

    @Test func progressPercentageClampsNegative() {
        let formatted = ReaderBottomOverlay.formatProgress(-0.5)
        #expect(formatted == "0%")
    }

    @Test func progressPercentageClampsAboveOne() {
        let formatted = ReaderBottomOverlay.formatProgress(1.5)
        #expect(formatted == "100%")
    }
}
