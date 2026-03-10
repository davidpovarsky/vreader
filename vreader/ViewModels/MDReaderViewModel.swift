// Purpose: ViewModel for the Markdown reader view. Manages reading state,
// position persistence (via ReaderPositionService), session tracking, and rendered content.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Position persistence delegated to ReaderPositionService (WI-008c).
// - File loading delegated to MDFileLoader (WI-008c).
// - Integrates ReadingSessionTracker for reading time tracking.
// - Uses protocol abstractions for testability (parser, persistence, tracker).
// - Position uses canonical UTF-16 offsets over rendered text.
// - Empty document: totalProgression = nil (no division by zero).
//
// @coordinates-with: MDFileLoader.swift, ReaderPositionService.swift,
//   MDParserProtocol.swift, ReadingPositionPersisting.swift,
//   ReadingSessionTracker.swift, LocatorFactory.swift, TXTTextViewBridge.swift

import Foundation

/// ViewModel for the Markdown reader screen.
@Observable
@MainActor
final class MDReaderViewModel {

    // MARK: - Constants

    /// Periodic flush interval for session duration (seconds).
    static let sessionFlushInterval: TimeInterval = 60.0

    // MARK: - Published State

    /// Rendered plain text (nil until open completes).
    private(set) var renderedText: String?

    /// Rendered attributed string for rich display (nil until open completes).
    private(set) var renderedAttributedString: NSAttributedString?

    /// Total rendered text length in UTF-16 code units.
    private(set) var renderedTextLengthUTF16: Int = 0

    /// Current scroll position as UTF-16 char offset.
    private(set) var currentOffsetUTF16: Int = 0

    /// Whether the file is currently loading.
    private(set) var isLoading = false

    /// Error message from the last failed operation.
    private(set) var errorMessage: String?

    /// Formatted session reading time (e.g., "5m").
    private(set) var sessionTimeDisplay: String?

    // MARK: - Computed State

    /// Total progression through the document (0.0 to 1.0). Nil for empty files.
    var totalProgression: Double? {
        guard renderedTextLengthUTF16 > 0 else { return nil }
        return Double(currentOffsetUTF16) / Double(renderedTextLengthUTF16)
    }

    // MARK: - Dependencies

    let bookFingerprint: DocumentFingerprint
    let bookFingerprintKey: String
    private let parser: any MDParserProtocol
    private let positionStore: any ReadingPositionPersisting
    private let sessionTracker: ReadingSessionTracker
    private let positionService: ReaderPositionService

    // MARK: - Private State

    private var flushTask: Task<Void, Never>?
    private var segmentStartDate: Date?
    private var accumulatedActiveSeconds: TimeInterval = 0
    /// Generation counter to guard against open/close races.
    private var openGeneration: Int = 0
    /// True after open() completes position restore. Guards close() from saving
    /// stale position 0 when close() races with an in-progress open().
    private var isOpenComplete = false

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        parser: any MDParserProtocol,
        positionStore: any ReadingPositionPersisting,
        sessionTracker: ReadingSessionTracker,
        deviceId: String,
        positionSaveDebounceNs: UInt64 = 2_000_000_000
    ) {
        self.bookFingerprint = bookFingerprint
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.parser = parser
        self.positionStore = positionStore
        self.sessionTracker = sessionTracker
        self.positionService = ReaderPositionService(
            bookFingerprintKey: bookFingerprint.canonicalKey,
            deviceId: deviceId,
            persistence: positionStore,
            debounceNanoseconds: positionSaveDebounceNs
        )
    }

    // MARK: - Lifecycle

    /// Opens the Markdown file, parses it, and restores the saved reading position.
    func open(url: URL) async {
        guard !isLoading else { return }

        // Guard against re-open
        if renderedText != nil {
            await close()
        }

        openGeneration += 1
        let myGeneration = openGeneration
        isOpenComplete = false

        isLoading = true
        errorMessage = nil

        // Stage 1+2: Read, parse, and restore position (via MDFileLoader)
        let loadResult: MDLoadResult
        do {
            loadResult = try await MDFileLoader.load(
                url: url,
                parser: parser,
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
            errorMessage = "Failed to open file."
            return
        }

        // Guard: another open() may have started while we were loading
        guard myGeneration == openGeneration else {
            isLoading = false
            return
        }

        renderedText = loadResult.documentInfo.renderedText
        renderedAttributedString = loadResult.documentInfo.renderedAttributedString
        renderedTextLengthUTF16 = loadResult.documentInfo.renderedTextLengthUTF16
        currentOffsetUTF16 = loadResult.restoredOffsetUTF16

        // Stage 3: Start reading session (rollback on failure)
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            renderedText = nil
            renderedAttributedString = nil
            renderedTextLengthUTF16 = 0
            currentOffsetUTF16 = 0
            isLoading = false
            errorMessage = "Failed to start reading session."
            return
        }
        segmentStartDate = Date()
        accumulatedActiveSeconds = 0

        // Stage 4: Update last opened (non-fatal)
        try? await positionStore.updateLastOpened(
            bookFingerprintKey: bookFingerprintKey,
            date: Date()
        )

        startPeriodicFlush()
        isOpenComplete = true
        isLoading = false
    }

    /// Closes the reader, ending the session and flushing state.
    /// Order is load-bearing (bugs #34, #45): saveNow → recordProgress → end → stats → notify.
    func close() async {
        // Invalidate generation so any in-flight open() becomes stale
        openGeneration += 1

        flushTask?.cancel()
        flushTask = nil

        if renderedText != nil, isOpenComplete {
            let locator = makeLocator()
            await positionService.saveNow(locator: locator)
            sessionTracker.recordProgress(locator: locator)
        }

        sessionTracker.endSessionIfNeeded()

        if let persistence = positionStore as? PersistenceActor {
            try? await persistence.recomputeStats(
                bookFingerprintKey: bookFingerprintKey,
                bookFingerprint: bookFingerprint
            )
        }

        NotificationCenter.default.post(name: .readerDidClose, object: bookFingerprintKey)

        resetState()
    }

    /// Called when the app moves to background while reader is open.
    /// Awaits the position save to guarantee it completes before iOS suspends.
    func onBackground() async {
        if renderedText != nil {
            let locator = makeLocator()
            await positionService.saveNow(locator: locator)
        }

        if let start = segmentStartDate {
            accumulatedActiveSeconds += Date().timeIntervalSince(start)
            segmentStartDate = nil
        }

        sessionTracker.pause()
        flushTask?.cancel()
        flushTask = nil
    }

    /// Called when the app returns to foreground with reader open.
    func onForeground() {
        guard renderedText != nil else { return }
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            errorMessage = "Failed to resume reading session."
            return
        }
        if segmentStartDate == nil { segmentStartDate = Date() }
        startPeriodicFlush()
    }

    // MARK: - Position Updates

    /// Called when the scroll position changes. Offset is in UTF-16 code units.
    func updateScrollPosition(charOffsetUTF16: Int) {
        let clamped = clampOffset(charOffsetUTF16)
        currentOffsetUTF16 = clamped

        let lightLocator = makeLightLocator()
        sessionTracker.recordProgress(locator: lightLocator)

        updateTimeDisplays()
        positionService.scheduleSave(locator: makeLocator())
    }

    // MARK: - Private: Locator Construction

    private func makeLightLocator() -> Locator {
        let progression: Double? = renderedTextLengthUTF16 > 0
            ? Double(currentOffsetUTF16) / Double(renderedTextLengthUTF16)
            : nil

        return LocatorFactory.mdPosition(
            fingerprint: bookFingerprint,
            charOffsetUTF16: currentOffsetUTF16,
            totalProgression: progression
        ) ?? Locator(
            bookFingerprint: bookFingerprint,
            href: nil, progression: nil, totalProgression: progression,
            cfi: nil, page: nil,
            charOffsetUTF16: currentOffsetUTF16,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    func makeLocator() -> Locator {
        let progression: Double? = renderedTextLengthUTF16 > 0
            ? Double(currentOffsetUTF16) / Double(renderedTextLengthUTF16)
            : nil

        return LocatorFactory.mdPosition(
            fingerprint: bookFingerprint,
            charOffsetUTF16: currentOffsetUTF16,
            totalProgression: progression,
            sourceText: renderedText
        ) ?? Locator(
            bookFingerprint: bookFingerprint,
            href: nil, progression: nil, totalProgression: progression,
            cfi: nil, page: nil,
            charOffsetUTF16: currentOffsetUTF16,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    // MARK: - Private: Session Time Tracking

    private func startPeriodicFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.sessionFlushInterval))
                    guard let self else { break }
                    try sessionTracker.periodicFlush()
                    updateTimeDisplays()
                } catch is CancellationError {
                    break
                } catch {
                    // Non-fatal
                }
            }
        }
    }

    private func updateTimeDisplays() {
        var total = accumulatedActiveSeconds
        if let start = segmentStartDate {
            total += Date().timeIntervalSince(start)
        }
        let sessionSeconds = Int(total)
        sessionTimeDisplay = ReadingTimeFormatter.formatReadingTime(totalSeconds: sessionSeconds)
    }

    // MARK: - Private: State Reset

    private func resetState() {
        renderedText = nil
        renderedAttributedString = nil
        renderedTextLengthUTF16 = 0
        currentOffsetUTF16 = 0
        segmentStartDate = nil
        accumulatedActiveSeconds = 0
        sessionTimeDisplay = nil
        isOpenComplete = false
    }

    // MARK: - Private: Offset Clamping

    private func clampOffset(_ offset: Int) -> Int {
        min(max(offset, 0), renderedTextLengthUTF16)
    }
}

// MARK: - TXTTextViewBridgeDelegate Conformance

#if canImport(UIKit)
extension MDReaderViewModel: TXTTextViewBridgeDelegate {
    func scrollPositionDidChange(topCharOffsetUTF16: Int) {
        updateScrollPosition(charOffsetUTF16: topCharOffsetUTF16)
    }

    func selectionDidChange(utf16Range: UTF16Range) {
        // MD reader does not support selection tracking yet
    }
}
#endif
