// Purpose: UI tests for reading position persistence (Bug #24).
// Verifies that the reading position is saved when navigating away
// and restored when reopening the same book.
//
// Uses --seed-position-test to create a real TXT file with scrollable content.
//
// @coordinates-with: TXTReaderContainerView.swift, TXTReaderViewModel.swift,
//   TestSeeder.swift, LaunchHelper.swift

import XCTest

@MainActor
final class PositionPersistenceTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .positionTest)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Position Persistence

    func testTXTReaderLoadsContent() {
        tapBook(titled: "Position Test Book", in: app)

        // Wait for the reader container to appear
        let container = app.otherElements[AccessibilityID.txtReaderContainer]
        XCTAssertTrue(
            container.waitForExistence(timeout: 10),
            "TXT reader container should appear"
        )

        // Wait for content to load (loading spinner disappears)
        let loading = app.otherElements["txtReaderLoading"]
        if loading.exists {
            XCTAssertTrue(
                loading.waitForDisappearance(timeout: 10),
                "Loading indicator should disappear once content loads"
            )
        }

        // Content should be visible (either regular or chunked)
        let content = app.otherElements[AccessibilityID.txtReaderContent]
        let chunked = app.otherElements[AccessibilityID.txtReaderChunkedContent]
        let contentLoaded = content.waitForExistence(timeout: 5) || chunked.waitForExistence(timeout: 2)
        XCTAssertTrue(contentLoaded, "Reader content should be visible")
    }

    func testPositionSavedOnNavigateBack() {
        tapBook(titled: "Position Test Book", in: app)

        // Wait for content to load
        let container = app.otherElements[AccessibilityID.txtReaderContainer]
        XCTAssertTrue(container.waitForExistence(timeout: 10))

        let content = app.otherElements[AccessibilityID.txtReaderContent]
        let chunked = app.otherElements[AccessibilityID.txtReaderChunkedContent]
        let readerContent = content.exists ? content : chunked
        guard readerContent.waitForExistence(timeout: 10) else {
            XCTFail("Reader content did not load")
            return
        }

        // Scroll down several times to move away from the beginning
        for _ in 0..<5 {
            readerContent.swipeUp()
        }

        // Wait for debounce save to fire (2s debounce + margin)
        sleep(3)

        // Navigate back to library
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()

        // Verify library appears
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library should appear after navigating back"
        )

        // Reopen the same book
        tapBook(titled: "Position Test Book", in: app)

        // Wait for container to appear and check restore offset
        let containerAgain = app.otherElements[AccessibilityID.txtReaderContainer]
        XCTAssertTrue(
            containerAgain.waitForExistence(timeout: 10),
            "TXT reader should reopen"
        )

        // Wait for content to load
        let contentAgain = app.otherElements[AccessibilityID.txtReaderContent]
        let chunkedAgain = app.otherElements[AccessibilityID.txtReaderChunkedContent]
        let contentReloaded = contentAgain.waitForExistence(timeout: 10)
            || chunkedAgain.waitForExistence(timeout: 5)
        XCTAssertTrue(contentReloaded, "Content should reload")

        // Check the accessibility value for restored offset
        // The container exposes "restoredOffset:N" where N > 0 means position was restored
        let value = containerAgain.value as? String ?? ""
        XCTAssertTrue(
            value.contains("restoredOffset:") && !value.contains("restoredOffset:0")
                && !value.contains("restoredOffset:none"),
            "Position should be restored to a non-zero offset, got: \(value)"
        )
    }

    func testPositionSurvivesAppRelaunch() {
        tapBook(titled: "Position Test Book", in: app)

        // Wait for content to load
        let content = app.otherElements[AccessibilityID.txtReaderContent]
        let chunked = app.otherElements[AccessibilityID.txtReaderChunkedContent]
        let readerContent = content.waitForExistence(timeout: 10)
            ? content : chunked
        guard readerContent.waitForExistence(timeout: 10) else {
            XCTFail("Reader content did not load")
            return
        }

        // Scroll down
        for _ in 0..<5 {
            readerContent.swipeUp()
        }

        // Wait for debounce save
        sleep(3)

        // Navigate back to ensure close() saves position
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // Relaunch the app (simulates force-kill + cold start)
        // Use .keepExisting to preserve the database (including saved position)
        app.terminate()
        app = launchApp(seed: .keepExisting)

        // Reopen the book
        tapBook(titled: "Position Test Book", in: app)

        let container = app.otherElements[AccessibilityID.txtReaderContainer]
        XCTAssertTrue(container.waitForExistence(timeout: 10))

        let contentAfterRelaunch = app.otherElements[AccessibilityID.txtReaderContent]
        let chunkedAfterRelaunch = app.otherElements[AccessibilityID.txtReaderChunkedContent]
        let loaded = contentAfterRelaunch.waitForExistence(timeout: 10)
            || chunkedAfterRelaunch.waitForExistence(timeout: 5)
        XCTAssertTrue(loaded, "Content should load after relaunch")

        // Verify position was restored
        let value = container.value as? String ?? ""
        XCTAssertTrue(
            value.contains("restoredOffset:") && !value.contains("restoredOffset:0")
                && !value.contains("restoredOffset:none"),
            "Position should be restored after app relaunch, got: \(value)"
        )
    }
}
