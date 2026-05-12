// Purpose: Reusable helpers for opening/closing the reader settings panel
// and scrolling to named sections. Used by Verification UITests (feature #45).
//
// Key decisions:
// - All methods are @MainActor to match XCUITest calling patterns.
// - openReaderSettings taps readerSettingsButton and waits for the panel.
// - scrollToSection uses label-match swipeUp to reach section headers.
// - closeReaderSettings dismisses via swipeDown on the sheet.
//
// @coordinates-with: ReaderSettingsPanel.swift, LaunchHelper.swift,
//   TestConstants.swift

import XCTest

/// Helpers for navigating the reader settings panel in UITests.
struct VerificationSettingsHelper {
    let app: XCUIApplication

    // MARK: - Panel lifecycle

    /// Taps the reader settings button and waits for the settings panel.
    /// - Returns: The settings panel element once it exists.
    @discardableResult
    func openReaderSettings(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(
            settingsButton.waitForHittable(timeout: 5),
            "Reader settings button should be hittable",
            file: file, line: line
        )
        settingsButton.tap()

        let panel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "Reader settings panel should appear",
            file: file, line: line
        )
        return panel
    }

    /// Closes the reader settings panel by swiping down.
    func closeReaderSettings(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let panel = app.otherElements[AccessibilityID.readerSettingsPanel]
        guard panel.exists else { return }
        panel.swipeDown()
        _ = panel.waitForDisappearance(timeout: 3)
    }

    // MARK: - Section navigation

    /// Scrolls within the settings panel until a static text element with
    /// the given section header label is visible. Attempts up to `maxSwipes`
    /// upward swipes before giving up.
    ///
    /// - Parameters:
    ///   - sectionHeader: The section title exactly as it appears in the panel.
    ///   - panel: The panel element to scroll within.
    ///   - maxSwipes: Maximum number of swipe attempts.
    func scrollToSection(
        _ sectionHeader: String,
        in panel: XCUIElement,
        maxSwipes: Int = 6,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<maxSwipes {
            // Direct label lookup avoids NSPredicate Sendable issues
            let header = panel.staticTexts[sectionHeader]
            if header.exists {
                return
            }
            panel.swipeUp()
        }
        let header = panel.staticTexts[sectionHeader]
        XCTAssertTrue(
            header.exists,
            "Could not find section header '\(sectionHeader)' in settings panel after \(maxSwipes) swipes",
            file: file, line: line
        )
    }
}
