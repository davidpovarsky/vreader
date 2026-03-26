// Purpose: Tests for FoliateReaderViewModel — relocate handling, book-ready lifecycle,
// error handling, locator construction, initial state verification.
//
// All tests are RED phase — they assert behavior the stub ViewModel does not yet implement.
//
// @coordinates-with: FoliateReaderViewModel.swift, FoliateTypes.swift,
//   Locator.swift, DocumentFingerprint.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let azw3Fingerprint = DocumentFingerprint(
    contentSHA256: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
    fileByteCount: 120000,
    format: .azw3
)

private let sampleRelocateEvent = FoliateRelocateEvent(
    cfi: "epubcfi(/6/14!/4/2/1:0)",
    fraction: 0.23,
    sectionIndex: 5,
    sectionTotal: 65,
    tocLabel: "Chapter 5",
    tocHref: "chapter5.xhtml"
)

/// A relocate event at the very start of the book.
private let startRelocateEvent = FoliateRelocateEvent(
    cfi: "epubcfi(/6/2!/4/2)",
    fraction: 0.0,
    sectionIndex: 0,
    sectionTotal: 65,
    tocLabel: "Cover",
    tocHref: "cover.xhtml"
)

/// A relocate event at the end of the book.
private let endRelocateEvent = FoliateRelocateEvent(
    cfi: "epubcfi(/6/130!/4/2)",
    fraction: 1.0,
    sectionIndex: 64,
    sectionTotal: 65,
    tocLabel: "Appendix",
    tocHref: nil
)

/// A relocate event with no TOC label.
private let noTOCRelocateEvent = FoliateRelocateEvent(
    cfi: "epubcfi(/6/8!/4/2)",
    fraction: 0.1,
    sectionIndex: 3,
    sectionTotal: 65,
    tocLabel: nil,
    tocHref: nil
)

// MARK: - Helpers

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
private func makeViewModel(
    fingerprint: DocumentFingerprint = azw3Fingerprint
) -> FoliateReaderViewModel {
    FoliateReaderViewModel(
        bookFingerprint: fingerprint,
        positionStore: StubPositionStore(),
        sessionTracker: ReadingSessionTracker(
            clock: SystemClock(),
            store: StubSessionStore(),
            deviceId: "test"
        ),
        deviceId: "test"
    )
}

// MARK: - Initial State

@Suite("FoliateReaderViewModel - Initial State")
@MainActor
struct FoliateReaderViewModelInitialStateTests {

    @Test("initial state: isLoading is true")
    func initialIsLoading() {
        let vm = makeViewModel()
        #expect(vm.isLoading == true)
    }

    @Test("initial state: currentCFI is nil")
    func initialCurrentCFI() {
        let vm = makeViewModel()
        #expect(vm.currentCFI == nil)
    }

    @Test("initial state: errorMessage is nil")
    func initialErrorMessage() {
        let vm = makeViewModel()
        #expect(vm.errorMessage == nil)
    }

    @Test("initial state: currentProgress is 0")
    func initialProgress() {
        let vm = makeViewModel()
        #expect(vm.currentProgress == 0)
    }

    @Test("initial state: currentTOCLabel is nil")
    func initialTOCLabel() {
        let vm = makeViewModel()
        #expect(vm.currentTOCLabel == nil)
    }

    @Test("initial state: currentLocator returns nil before any relocate")
    func initialLocatorNil() {
        let vm = makeViewModel()
        #expect(vm.currentLocator() == nil)
    }

    @Test("initial state: bookFingerprint matches init parameter")
    func initialBookFingerprint() {
        let vm = makeViewModel()
        #expect(vm.bookFingerprint == azw3Fingerprint)
    }
}

// MARK: - handleRelocate

@Suite("FoliateReaderViewModel - handleRelocate")
@MainActor
struct FoliateReaderViewModelRelocateTests {

    @Test("handleRelocate updates currentCFI")
    func relocateUpdatesCFI() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)
        #expect(vm.currentCFI == "epubcfi(/6/14!/4/2/1:0)")
    }

    @Test("handleRelocate updates currentProgress from fraction")
    func relocateUpdatesProgress() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)
        #expect(abs(vm.currentProgress - 0.23) < 0.001)
    }

    @Test("handleRelocate updates currentTOCLabel")
    func relocateUpdatesTOCLabel() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)
        #expect(vm.currentTOCLabel == "Chapter 5")
    }

    @Test("handleRelocate with nil tocLabel sets currentTOCLabel to nil")
    func relocateNilTOCLabel() {
        let vm = makeViewModel()
        // First set a label
        vm.handleRelocate(sampleRelocateEvent)
        // Then relocate to section with no label
        vm.handleRelocate(noTOCRelocateEvent)
        #expect(vm.currentTOCLabel == nil)
    }

    @Test("handleRelocate at book start sets progress to 0")
    func relocateAtStart() {
        let vm = makeViewModel()
        vm.handleRelocate(startRelocateEvent)
        #expect(vm.currentProgress == 0.0)
        #expect(vm.currentCFI == "epubcfi(/6/2!/4/2)")
    }

    @Test("handleRelocate at book end sets progress to 1.0")
    func relocateAtEnd() {
        let vm = makeViewModel()
        vm.handleRelocate(endRelocateEvent)
        #expect(vm.currentProgress == 1.0)
    }

    @Test("handleRelocate overwrites previous position on second call")
    func relocateOverwritesPrevious() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)
        vm.handleRelocate(endRelocateEvent)

        #expect(vm.currentCFI == "epubcfi(/6/130!/4/2)")
        #expect(vm.currentProgress == 1.0)
        #expect(vm.currentTOCLabel == "Appendix")
    }

    @Test("handleRelocate with different fingerprint still uses VM fingerprint for locator")
    func relocateLocatorUsesVMFingerprint() {
        // The relocate event itself doesn't carry a fingerprint — the VM does.
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)

        let locator = vm.currentLocator()
        #expect(locator != nil)
        #expect(locator?.bookFingerprint == azw3Fingerprint)
    }
}

// MARK: - handleBookReady

@Suite("FoliateReaderViewModel - handleBookReady")
@MainActor
struct FoliateReaderViewModelBookReadyTests {

    @Test("handleBookReady sets isLoading to false")
    func bookReadySetsLoadingFalse() {
        let vm = makeViewModel()
        #expect(vm.isLoading == true) // precondition
        vm.handleBookReady("Test Book", sections: 10)
        #expect(vm.isLoading == false)
    }

    @Test("handleBookReady clears any previous error")
    func bookReadyClearsError() {
        let vm = makeViewModel()
        vm.handleError("Some error")
        vm.handleBookReady("Test Book", sections: 10)
        #expect(vm.errorMessage == nil)
    }

    @Test("handleBookReady with zero sections still sets isLoading false")
    func bookReadyZeroSections() {
        let vm = makeViewModel()
        vm.handleBookReady("Empty Book", sections: 0)
        #expect(vm.isLoading == false)
    }
}

// MARK: - handleError

@Suite("FoliateReaderViewModel - handleError")
@MainActor
struct FoliateReaderViewModelErrorTests {

    @Test("handleError sets errorMessage")
    func errorSetsMessage() {
        let vm = makeViewModel()
        vm.handleError("This file is DRM-protected.")
        #expect(vm.errorMessage == "This file is DRM-protected.")
    }

    @Test("handleError overwrites previous error")
    func errorOverwritesPrevious() {
        let vm = makeViewModel()
        vm.handleError("First error")
        vm.handleError("Second error")
        #expect(vm.errorMessage == "Second error")
    }

    @Test("handleError preserves isLoading state")
    func errorPreservesLoading() {
        let vm = makeViewModel()
        #expect(vm.isLoading == true)
        vm.handleError("Parse failure")
        // Error during loading should not auto-clear isLoading — that's bookReady's job.
        // The VM should set isLoading = false on error so the UI can show the error.
        // This test verifies the error handler manages the loading state properly.
        #expect(vm.isLoading == false)
    }
}

// MARK: - currentLocator

@Suite("FoliateReaderViewModel - currentLocator")
@MainActor
struct FoliateReaderViewModelLocatorTests {

    @Test("currentLocator returns nil before any relocate")
    func locatorNilBeforeRelocate() {
        let vm = makeViewModel()
        #expect(vm.currentLocator() == nil)
    }

    @Test("currentLocator returns Locator with correct cfi after relocate")
    func locatorHasCorrectCFI() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)

        let locator = vm.currentLocator()
        #expect(locator != nil)
        #expect(locator?.cfi == "epubcfi(/6/14!/4/2/1:0)")
    }

    @Test("currentLocator returns Locator with correct totalProgression")
    func locatorHasCorrectTotalProgression() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)

        let locator = vm.currentLocator()
        #expect(locator != nil)
        guard let tp = locator?.totalProgression else {
            Issue.record("Expected non-nil totalProgression")
            return
        }
        #expect(abs(tp - 0.23) < 0.001)
    }

    @Test("currentLocator returns Locator with bookFingerprint")
    func locatorHasBookFingerprint() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)

        let locator = vm.currentLocator()
        #expect(locator?.bookFingerprint == azw3Fingerprint)
    }

    @Test("currentLocator includes tocLabel as href")
    func locatorIncludesTOCAsHref() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)

        let locator = vm.currentLocator()
        // The locator should carry the TOC href for section identification
        #expect(locator?.href == "chapter5.xhtml")
    }

    @Test("currentLocator at progress 0 has totalProgression 0")
    func locatorAtStartHasZeroProgression() {
        let vm = makeViewModel()
        vm.handleRelocate(startRelocateEvent)

        let locator = vm.currentLocator()
        #expect(locator != nil)
        #expect(locator?.totalProgression == 0.0)
    }

    @Test("currentLocator at progress 1.0 has totalProgression 1.0")
    func locatorAtEndHasFullProgression() {
        let vm = makeViewModel()
        vm.handleRelocate(endRelocateEvent)

        let locator = vm.currentLocator()
        #expect(locator != nil)
        #expect(locator?.totalProgression == 1.0)
    }

    @Test("currentLocator updates after second relocate")
    func locatorUpdatesAfterSecondRelocate() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)
        vm.handleRelocate(endRelocateEvent)

        let locator = vm.currentLocator()
        #expect(locator?.cfi == "epubcfi(/6/130!/4/2)")
        #expect(locator?.totalProgression == 1.0)
    }

    @Test("currentLocator has nil page field (not a PDF)")
    func locatorHasNilPage() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)

        let locator = vm.currentLocator()
        #expect(locator?.page == nil)
    }

    @Test("currentLocator has nil charOffsetUTF16 field (not a TXT)")
    func locatorHasNilCharOffset() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)

        let locator = vm.currentLocator()
        #expect(locator?.charOffsetUTF16 == nil)
    }

    @Test("currentLocator validates successfully")
    func locatorPassesValidation() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)

        let locator = vm.currentLocator()
        #expect(locator != nil)
        #expect(locator?.validate() == nil) // nil means valid
    }
}

// MARK: - State Transitions

@Suite("FoliateReaderViewModel - State Transitions")
@MainActor
struct FoliateReaderViewModelStateTransitionTests {

    @Test("full lifecycle: loading -> bookReady -> relocate -> locator")
    func fullLifecycle() {
        let vm = makeViewModel()

        // Phase 1: Initial — loading
        #expect(vm.isLoading == true)
        #expect(vm.currentLocator() == nil)

        // Phase 2: Book ready — no longer loading
        vm.handleBookReady("Test AZW3", sections: 65)
        #expect(vm.isLoading == false)

        // Phase 3: First relocate — position known
        vm.handleRelocate(startRelocateEvent)
        #expect(vm.currentCFI != nil)
        #expect(vm.currentProgress == 0.0)

        // Phase 4: Navigate — position updates
        vm.handleRelocate(sampleRelocateEvent)
        #expect(vm.currentCFI == "epubcfi(/6/14!/4/2/1:0)")
        #expect(abs(vm.currentProgress - 0.23) < 0.001)

        // Phase 5: Locator reflects final state
        let locator = vm.currentLocator()
        #expect(locator != nil)
        #expect(locator?.bookFingerprint == azw3Fingerprint)
        #expect(locator?.cfi == "epubcfi(/6/14!/4/2/1:0)")
    }

    @Test("error during loading: loading -> error -> locator still nil")
    func errorDuringLoading() {
        let vm = makeViewModel()

        #expect(vm.isLoading == true)
        vm.handleError("DRM-protected file")

        #expect(vm.errorMessage == "DRM-protected file")
        #expect(vm.isLoading == false)
        #expect(vm.currentLocator() == nil)
    }

    @Test("error then bookReady: error is cleared")
    func errorThenBookReady() {
        let vm = makeViewModel()

        vm.handleError("Transient parse error")
        #expect(vm.errorMessage != nil)

        vm.handleBookReady("Recovered Book", sections: 10)
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)
    }

    @Test("relocate before bookReady still updates position")
    func relocateBeforeBookReady() {
        let vm = makeViewModel()

        // Relocate can arrive before bookReady in some edge cases
        vm.handleRelocate(sampleRelocateEvent)
        #expect(vm.currentCFI == "epubcfi(/6/14!/4/2/1:0)")

        // Locator should still work
        let locator = vm.currentLocator()
        #expect(locator != nil)
    }
}

// MARK: - Boundary: Different Fingerprints

@Suite("FoliateReaderViewModel - Fingerprint Variations")
@MainActor
struct FoliateReaderViewModelFingerprintTests {

    @Test("locator uses epub fingerprint for EPUB format")
    func epubFingerprint() {
        let epubFP = DocumentFingerprint(
            contentSHA256: "1111111111111111111111111111111111111111111111111111111111111111",
            fileByteCount: 500000,
            format: .epub
        )
        let vm = makeViewModel(fingerprint: epubFP)
        vm.handleRelocate(sampleRelocateEvent)

        let locator = vm.currentLocator()
        #expect(locator?.bookFingerprint.format == .epub)
        #expect(locator?.bookFingerprint == epubFP)
    }

    @Test("locator uses azw3 fingerprint for AZW3 format")
    func azw3Fingerprint() {
        let vm = makeViewModel()
        vm.handleRelocate(sampleRelocateEvent)

        let locator = vm.currentLocator()
        #expect(locator?.bookFingerprint.format == .azw3)
    }
}
