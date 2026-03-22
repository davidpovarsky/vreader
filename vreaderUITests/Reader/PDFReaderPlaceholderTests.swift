// WI-UI-8: PDF Reader Container — Reader State
//
// Tests verify the PDF reader container appears when navigating
// to a PDF book. PDFKit integration is fully wired.

import XCTest

@MainActor
final class PDFReaderPlaceholderTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testPDFReaderContainerAppears() {
        tapBook(titled: "Test PDF Document", in: app)

        let container = app.otherElements[AccessibilityID.pdfReaderContainer]
        XCTAssertTrue(
            container.waitForExistence(timeout: 5),
            "PDF reader container should appear when opening a PDF book"
        )
    }
}
