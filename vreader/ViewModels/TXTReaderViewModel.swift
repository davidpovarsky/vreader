// Purpose: ViewModel for the TXT reader view. Manages reading state,
// position persistence (via ReaderPositionService), session tracking,
// and word count estimation.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Position persistence delegated to ReaderPositionService (WI-008d).
// - File loading delegated to TXTFileLoader (WI-008d).
// - Lifecycle operations (session, flush, time display) delegated to ReaderLifecycleHelper (R6).
// - Uses protocol abstractions for testability (service, persistence, tracker).
// - Staged error handling: service failure aborts, position/timestamp failures non-fatal.
// - Position uses canonical UTF-16 offsets matching TXTOffsetMapper conventions.
// - wordsRead estimated via Section 9.6 normative formula.
//
// @coordinates-with: TXTFileLoader.swift, ReaderLifecycleHelper.swift,
//   ReaderPositionService.swift, TXTServiceProtocol.swift,
//   ReadingPositionPersisting.swift, ReadingSessionTracker.swift,
//   LocatorFactory.swift, TXTTextViewBridge.swift

import Foundation

/// ViewModel for the TXT reader screen.
@Observable
@MainActor
final class TXTReaderViewModel {

    // MARK: - Published State

    /// Decoded text content (nil until open completes).
    private(set) var textContent: String?

    /// Total text length in UTF-16 code units.
    private(set) var totalTextLengthUTF16: Int = 0

    /// Total word count from metadata.
    private(set) var totalWordCount: Int = 0

    /// Current scroll position as UTF-16 char offset.
    private(set) var currentOffsetUTF16: Int = 0

    /// Start of current selection in UTF-16 offsets (nil if no selection).
    private(set) var currentSelectionStart: Int?

    /// End of current selection in UTF-16 offsets (nil if no selection).
    private(set) var currentSelectionEnd: Int?

    /// Whether the file is currently loading.
    private(set) var isLoading = false

    /// Error message from the last failed operation.
    private(set) var errorMessage: String?

    /// Formatted session reading time (e.g., "5m"). Delegated to lifecycle helper.
    var sessionTimeDisplay: String? { lifecycle.sessionTimeDisplay }

    // MARK: - Computed State

    /// Total progression through the document (0.0 to 1.0). Nil for empty files.
    var totalProgression: Double? {
        guard totalTextLengthUTF16 > 0 else { return nil }
        return Double(currentOffsetUTF16) / Double(totalTextLengthUTF16)
    }

    /// Estimated words read based on Section 9.6 normative formula.
    /// `wordsRead = round((abs(endOffsetUTF16 - startOffsetUTF16) / totalLen) * totalWords)`
    /// Clamped to [0, totalWordCount]. Nil if no content loaded or empty.
    var estimatedWordsRead: Int? {
        guard textContent != nil, totalTextLengthUTF16 > 0, totalWordCount > 0 else {
            return nil
        }
        let startOffset = 0 // Reading always starts from beginning
        let fraction = Double(abs(currentOffsetUTF16 - startOffset)) / Double(totalTextLengthUTF16)
        let raw = (fraction * Double(totalWordCount)).rounded()
        return min(max(Int(raw), 0), totalWordCount)
    }

    // MARK: - Dependencies

    let bookFingerprint: DocumentFingerprint
    let bookFingerprintKey: String
    let lifecycle: ReaderLifecycleHelper
    private let txtService: any TXTServiceProtocol
    private let positionStore: any ReadingPositionPersisting
    private let sessionTracker: ReadingSessionTracker
    private let positionService: ReaderPositionService

    // MARK: - Private State

    /// Generation counter to guard against open/close races.
    private var openGeneration: Int = 0
    /// True after open() completes position restore. Guards close() from saving
    /// stale position 0 when close() races with an in-progress open().
    private var isOpenComplete = false
    /// Time until which scroll position saves are suppressed after a position restore.
    /// Handles any residual TextKit relayout callbacks that escape the bridge-level guard.
    private var restoreSuppressUntil: Date?
    /// Duration to suppress scroll saves after position restore (seconds).
    /// Must be longer than the bridge's Phase 2 restore delay (0.8s) + margin.
    private static let restoreSuppressDuration: TimeInterval = 1.5

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        txtService: any TXTServiceProtocol,
        positionStore: any ReadingPositionPersisting,
        sessionTracker: ReadingSessionTracker,
        deviceId: String,
        positionSaveDebounceNs: UInt64 = 2_000_000_000
    ) {
        self.bookFingerprint = bookFingerprint
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.txtService = txtService
        self.positionStore = positionStore
        self.sessionTracker = sessionTracker
        let posService = ReaderPositionService(
            bookFingerprintKey: bookFingerprint.canonicalKey,
            deviceId: deviceId,
            persistence: positionStore,
            debounceNanoseconds: positionSaveDebounceNs
        )
        self.positionService = posService
        self.lifecycle = ReaderLifecycleHelper(
            bookFingerprint: bookFingerprint,
            positionService: posService,
            sessionTracker: sessionTracker,
            positionStore: positionStore
        )
    }

    // MARK: - Lifecycle

    /// Opens the TXT file and restores the saved reading position.
    func open(url: URL) async {
        guard !isLoading else { return }

        // Guard against re-open: close previous state first
        if textContent != nil {
            await close()
        }

        openGeneration += 1
        let myGeneration = openGeneration
        isOpenComplete = false

        isLoading = true
        errorMessage = nil

        // Stage 1+2: Load, decode, and restore position (via TXTFileLoader)
        let loadResult: TXTLoadResult
        do {
            loadResult = try await TXTFileLoader.load(
                url: url,
                service: txtService,
                positionStore: positionStore,
                bookFingerprintKey: bookFingerprintKey
            )
        } catch is CancellationError {
            resetState()
            isLoading = false
            return
        } catch {
            resetState()
            isLoading = false
            errorMessage = (error as? TXTServiceError).map(describeServiceError)
                ?? "Failed to open file."
            return
        }

        // Guard: another open() may have started while we were awaiting.
        // Close the service we just opened so it doesn't leak in .alreadyOpen state.
        guard myGeneration == openGeneration else {
            await txtService.close()
            isLoading = false
            return
        }

        textContent = loadResult.metadata.text
        totalTextLengthUTF16 = loadResult.metadata.totalTextLengthUTF16
        totalWordCount = loadResult.metadata.totalWordCount
        currentOffsetUTF16 = loadResult.restoredOffsetUTF16

        restoreSuppressUntil = loadResult.hadSavedPosition
            ? Date().addingTimeInterval(Self.restoreSuppressDuration)
            : nil

        // Stage 3: Start reading session (rollback on failure)
        do {
            try lifecycle.beginSession()
        } catch {
            textContent = nil
            totalTextLengthUTF16 = 0
            totalWordCount = 0
            currentOffsetUTF16 = 0
            await txtService.close()
            isLoading = false
            errorMessage = "Failed to start reading session."
            return
        }

        // Stage 4: Update last opened (non-fatal)
        await lifecycle.updateLastOpened()
        isOpenComplete = true
        isLoading = false
    }

    /// Closes the reader, ending the session and flushing state.
    /// Order is load-bearing (bugs #34, #45): saveNow → recordProgress → end → stats → notify.
    func close() async {
        openGeneration += 1

        let locator = (textContent != nil && isOpenComplete) ? makeLocator() : nil
        await lifecycle.close(locator: locator)

        await txtService.close()
        resetState()
    }

    /// Called when the app moves to background while reader is open.
    /// Awaits the position save to guarantee it completes before iOS suspends.
    func onBackground() async {
        let locator = textContent != nil ? makeLocator() : nil
        await lifecycle.onBackground(locator: locator)
    }

    /// Called when the app returns to foreground with reader open.
    func onForeground() {
        guard textContent != nil else { return }
        if let error = lifecycle.onForeground() {
            errorMessage = error
        }
    }

    // MARK: - Position Updates

    /// Called when the scroll position changes. Offset is in UTF-16 code units.
    func updateScrollPosition(charOffsetUTF16: Int) {
        guard textContent != nil, isOpenComplete else { return }
        let clamped = clampOffset(charOffsetUTF16)

        // Suppress scroll position saves during the post-restore settling window.
        // TextKit relayout storms after position restore can fire scrollViewDidScroll
        // with wrong offsets (including near-zero). The bridge suppresses most of these,
        // but this is defense in depth.
        if let suppressUntil = restoreSuppressUntil {
            if Date() < suppressUntil {
                // Still track position for display, but don't persist.
                // This allows real user scrolls during the window to update the UI.
                currentOffsetUTF16 = clamped
                return
            }
            restoreSuppressUntil = nil
        }

        currentOffsetUTF16 = clamped

        lifecycle.recordProgressAndScheduleSave(locator: makeLocator())
    }

    // MARK: - Selection

    /// Called when the user's text selection changes.
    /// A zero-width range (start == end) is a cursor, not a selection — clear it.
    func updateSelection(startUTF16: Int, endUTF16: Int) {
        if startUTF16 == endUTF16 {
            currentSelectionStart = nil
            currentSelectionEnd = nil
        } else {
            currentSelectionStart = clampOffset(min(startUTF16, endUTF16))
            currentSelectionEnd = clampOffset(max(startUTF16, endUTF16))
        }
    }

    /// Clears the current selection.
    func clearSelection() {
        currentSelectionStart = nil
        currentSelectionEnd = nil
    }

    // MARK: - Private: Locator Construction

    /// Full locator with quote/context extraction (for persistence).
    /// Internal access for bookmark creation from container views.
    func makeLocator() -> Locator {
        let progression = totalTextLengthUTF16 > 0
            ? Double(currentOffsetUTF16) / Double(totalTextLengthUTF16)
            : 0.0

        return LocatorFactory.txtPosition(
            fingerprint: bookFingerprint,
            charOffsetUTF16: currentOffsetUTF16,
            totalProgression: progression,
            sourceText: textContent
        ) ?? Locator(
            bookFingerprint: bookFingerprint,
            href: nil, progression: nil, totalProgression: progression,
            cfi: nil, page: nil,
            charOffsetUTF16: currentOffsetUTF16,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    // MARK: - Private: State Reset

    private func resetState() {
        textContent = nil
        totalTextLengthUTF16 = 0
        totalWordCount = 0
        currentOffsetUTF16 = 0
        currentSelectionStart = nil
        currentSelectionEnd = nil
        isOpenComplete = false
        restoreSuppressUntil = nil
    }

    // MARK: - Private: Offset Clamping

    private func clampOffset(_ offset: Int) -> Int {
        min(max(offset, 0), totalTextLengthUTF16)
    }

    // MARK: - Private: Error Description

    private func describeServiceError(_ error: TXTServiceError) -> String {
        switch error {
        case .fileNotFound: return "The file could not be found."
        case .encodingDetectionFailed: return "Could not detect file encoding."
        case .decodingFailed: return "The file could not be decoded."
        case .notOpen: return "No file is currently open."
        case .alreadyOpen: return "A file is already open."
        }
    }
}

// MARK: - TXTTextViewBridgeDelegate Conformance

#if canImport(UIKit)
extension TXTReaderViewModel: TXTTextViewBridgeDelegate {
    func scrollPositionDidChange(topCharOffsetUTF16: Int) {
        updateScrollPosition(charOffsetUTF16: topCharOffsetUTF16)
    }

    func selectionDidChange(utf16Range: UTF16Range) {
        updateSelection(startUTF16: utf16Range.startUTF16, endUTF16: utf16Range.endUTF16)
    }
}
#endif
