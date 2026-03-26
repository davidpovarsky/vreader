// Purpose: Tests for FoliateReaderContainerView logic — error state tracking,
// selection event handling, overlay event dispatch.
//
// @coordinates-with: FoliateReaderContainerView.swift,
//   FoliateReaderContainerView+Highlights.swift,
//   FoliateReaderContainerView+Navigation.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let foliateFingerprint = DocumentFingerprint(
    contentSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    fileByteCount: 200000,
    format: .azw3
)

private struct StubPositionStore: ReadingPositionPersisting {
    func loadPosition(bookFingerprintKey: String) async throws -> Locator? { nil }
    func savePosition(bookFingerprintKey: String, locator: Locator, deviceId: String) async throws {}
    func updateLastOpened(bookFingerprintKey: String, date: Date) async throws {}
}

private struct StubSessionStore: SessionPersisting {
    func saveSession(_ session: ReadingSession) throws {}
    func discardSession(id: UUID) throws {}
    func flushDuration(sessionId: UUID, durationSeconds: Int) throws {}
    func fetchUnclosedSessions() throws -> [ReadingSession] { [] }
}

@MainActor
private func makeTestVM() -> FoliateReaderViewModel {
    FoliateReaderViewModel(
        bookFingerprint: foliateFingerprint,
        positionStore: StubPositionStore(),
        sessionTracker: ReadingSessionTracker(clock: SystemClock(), store: StubSessionStore(), deviceId: "test"),
        deviceId: "test"
    )
}

// MARK: - FoliateContainerErrorLogic

/// Tests the pure error-tracking logic extracted from the container view.
/// The container uses `showError = (viewModel.errorMessage != nil)`.
@Suite("FoliateContainerErrorLogic")
@MainActor
struct FoliateContainerErrorLogicTests {

    @Test("error message nil produces no error display")
    func noErrorWhenNil() {
        let vm = makeTestVM()
        #expect(FoliateContainerErrorLogic.shouldShowError(errorMessage: vm.errorMessage) == false)
    }

    @Test("non-nil error message produces error display")
    func errorWhenNonNil() {
        let vm = makeTestVM()
        vm.handleError("DRM protected")
        #expect(FoliateContainerErrorLogic.shouldShowError(errorMessage: vm.errorMessage) == true)
    }

    @Test("error cleared after book ready")
    func errorClearedAfterBookReady() {
        let vm = makeTestVM()
        vm.handleError("temp error")
        vm.handleBookReady("Book Title", sections: 10)
        #expect(FoliateContainerErrorLogic.shouldShowError(errorMessage: vm.errorMessage) == false)
    }

    @Test("empty error message still shows error")
    func emptyStringIsError() {
        // Edge case: empty string is non-nil, should still show error
        #expect(FoliateContainerErrorLogic.shouldShowError(errorMessage: "") == true)
    }
}

// MARK: - FoliateSelectionMapper

/// Tests the pure selection-to-notification mapping logic.
@Suite("FoliateSelectionMapper")
@MainActor
struct FoliateSelectionMapperTests {

    @Test("maps selection event to notification payload")
    func mapsSelectionToPayload() {
        let event = FoliateSelectionEvent(
            cfi: "epubcfi(/6/4!/4/2/3:5,/6/4!/4/2/3:42)",
            text: "selected text",
            rect: .init(x: 10, y: 20, width: 100, height: 30),
            sectionIndex: 3
        )
        let payload = FoliateSelectionMapper.notificationPayload(from: event)
        #expect(payload.selectedText == "selected text")
        #expect(payload.startUTF16 == 0) // Foliate uses CFI, not UTF-16 offsets
        #expect(payload.endUTF16 == 0)
    }

    @Test("maps empty text selection")
    func mapsEmptyText() {
        let event = FoliateSelectionEvent(
            cfi: "epubcfi(/6/4!/4/2)",
            text: "",
            rect: .zero,
            sectionIndex: 0
        )
        let payload = FoliateSelectionMapper.notificationPayload(from: event)
        #expect(payload.selectedText == "")
    }

    @Test("maps selection with CJK text")
    func mapsCJKText() {
        let event = FoliateSelectionEvent(
            cfi: "epubcfi(/6/4!/4/2/1:0,/6/4!/4/2/1:6)",
            text: "\u{4F60}\u{597D}\u{4E16}\u{754C}",
            rect: .init(x: 0, y: 0, width: 200, height: 40),
            sectionIndex: 1
        )
        let payload = FoliateSelectionMapper.notificationPayload(from: event)
        #expect(payload.selectedText == "\u{4F60}\u{597D}\u{4E16}\u{754C}")
    }
}

// MARK: - FoliateNavigationHelper

/// Tests the pure navigation logic extracted from the Navigation extension.
@Suite("FoliateNavigationHelper")
struct FoliateNavigationHelperTests {

    @Test("validates CFI string is non-empty for navigation")
    func validCFI() {
        #expect(FoliateNavigationHelper.isValidNavigationTarget(cfi: "epubcfi(/6/2)") == true)
    }

    @Test("rejects empty CFI")
    func emptyRejectsNavigation() {
        #expect(FoliateNavigationHelper.isValidNavigationTarget(cfi: "") == false)
    }

    @Test("rejects nil CFI")
    func nilRejectsNavigation() {
        #expect(FoliateNavigationHelper.isValidNavigationTarget(cfi: nil) == false)
    }

    @Test("rejects whitespace-only CFI")
    func whitespaceRejectsNavigation() {
        #expect(FoliateNavigationHelper.isValidNavigationTarget(cfi: "   ") == false)
    }
}
