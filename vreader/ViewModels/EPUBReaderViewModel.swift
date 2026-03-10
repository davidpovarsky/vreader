// Purpose: ViewModel for the EPUB reader view. Manages reading state,
// position persistence (via ReaderPositionService), session tracking, navigation.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Position persistence delegated to ReaderPositionService (WI-008b).
// - File loading delegated to EPUBFileLoader (WI-008b).
// - Active reading time excludes background/pause intervals.
// - Uses protocol abstractions for testability (parser, persistence, tracker).
// - Staged error handling: parser failure aborts, position/timestamp failures are non-fatal.
//
// @coordinates-with: EPUBFileLoader.swift, ReaderPositionService.swift,
//   EPUBParserProtocol.swift, ReadingPositionPersisting.swift,
//   ReadingSessionTracker.swift, LocatorFactory.swift

import Foundation

/// ViewModel for the EPUB reader screen.
@Observable
@MainActor
final class EPUBReaderViewModel {

    // MARK: - Constants

    /// Periodic flush interval for session duration (seconds).
    static let sessionFlushInterval: TimeInterval = 60.0

    // MARK: - Published State

    /// Current EPUB metadata (nil until open completes).
    private(set) var metadata: EPUBMetadata?

    /// Current reading position.
    private(set) var currentPosition: EPUBPosition?

    /// Whether the EPUB is currently loading.
    private(set) var isLoading = false

    /// Error message from the last failed operation.
    private(set) var errorMessage: String?

    /// Formatted session reading time (e.g., "5m").
    private(set) var sessionTimeDisplay: String?

    // Note: totalTimeDisplay and speedDisplay are deferred to WI-7
    // when cumulative reading stats are available from ReadingStats.

    /// Current spine item index for navigation display.
    var currentSpineIndex: Int {
        guard let position = currentPosition, let metadata else { return 0 }
        return metadata.spineItems.firstIndex(where: { $0.href == position.href }) ?? 0
    }

    // MARK: - Dependencies

    private let bookFingerprint: DocumentFingerprint
    let bookFingerprintKey: String
    private let parser: any EPUBParserProtocol
    private let positionStore: any ReadingPositionPersisting
    private let sessionTracker: ReadingSessionTracker
    private let positionService: ReaderPositionService

    // MARK: - Private State

    private var flushTask: Task<Void, Never>?
    /// Date when the current active segment started (reset on resume).
    private var segmentStartDate: Date?
    /// Accumulated active reading seconds (excluding paused time).
    private var accumulatedActiveSeconds: TimeInterval = 0

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        parser: any EPUBParserProtocol,
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

    /// Opens the EPUB file and restores the saved reading position.
    func open(url: URL) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        // Stage 1+2: Parse EPUB and restore position (via EPUBFileLoader)
        let loadResult: EPUBLoadResult
        do {
            loadResult = try await EPUBFileLoader.load(
                url: url,
                parser: parser,
                positionStore: positionStore,
                bookFingerprintKey: bookFingerprintKey
            )
        } catch {
            isLoading = false
            errorMessage = (error as? EPUBParserError).map(describeParserError)
                ?? "Failed to open book."
            return
        }

        metadata = loadResult.metadata
        currentPosition = loadResult.initialPosition

        // Stage 3: Start reading session (rollback parser + state on failure)
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            metadata = nil
            currentPosition = nil
            await parser.close()
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
        isLoading = false
    }

    /// Closes the reader, ending the session and flushing state.
    /// Order is load-bearing (bugs #34, #45): saveNow → recordProgress → end → stats → notify.
    func close() async {
        flushTask?.cancel()
        flushTask = nil

        if let position = currentPosition {
            let locator = makeLocator(from: position)
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

        await parser.close()
        metadata = nil
        currentPosition = nil
    }

    /// Called when the app moves to background while reader is open.
    /// Awaits the position save to guarantee it completes before iOS suspends.
    func onBackground() async {
        if let position = currentPosition {
            let locator = makeLocator(from: position)
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

    /// Called by the EPUB renderer when the reading position changes.
    func updatePosition(_ position: EPUBPosition) {
        currentPosition = position
        let locator = makeLocator(from: position)
        sessionTracker.recordProgress(locator: locator)
        updateTimeDisplays()
        positionService.scheduleSave(locator: locator)
    }

    // MARK: - Navigation

    /// Navigates to a specific spine item by index.
    func navigateToSpine(index: Int) {
        guard let metadata, index >= 0, index < metadata.spineItems.count else { return }
        let item = metadata.spineItems[index]
        let position = EPUBPosition(
            href: item.href,
            progression: 0,
            totalProgression: estimateTotalProgression(spineIndex: index),
            cfi: nil
        )
        updatePosition(position)
    }

    /// Navigates to the next spine item.
    func navigateNext() {
        navigateToSpine(index: currentSpineIndex + 1)
    }

    /// Navigates to the previous spine item.
    func navigatePrevious() {
        navigateToSpine(index: currentSpineIndex - 1)
    }

    // MARK: - Locator Construction

    /// Returns the locator for the current reading position.
    func makeCurrentLocator() -> Locator? {
        guard let position = currentPosition else { return nil }
        return makeLocator(from: position)
    }

    private func makeLocator(from position: EPUBPosition) -> Locator {
        LocatorFactory.epub(
            fingerprint: bookFingerprint,
            href: position.href,
            progression: position.progression,
            totalProgression: position.totalProgression,
            cfi: position.cfi
        ) ?? Locator(
            bookFingerprint: bookFingerprint,
            href: position.href,
            progression: position.progression,
            totalProgression: position.totalProgression,
            cfi: position.cfi,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: nil,
            textContextBefore: nil,
            textContextAfter: nil
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

    // MARK: - Private: Navigation Helpers

    private func estimateTotalProgression(spineIndex: Int) -> Double {
        guard let metadata, metadata.spineCount > 1 else { return 0 }
        return Double(spineIndex) / Double(metadata.spineCount - 1)
    }

    // MARK: - Private: Error Description

    private func describeParserError(_ error: EPUBParserError) -> String {
        switch error {
        case .fileNotFound: return "The book file could not be found."
        case .invalidFormat: return "This file is not a valid EPUB."
        case .parsingFailed: return "The book could not be read."
        case .notOpen: return "No book is currently open."
        case .alreadyOpen: return "A book is already open."
        case .resourceNotFound: return "A book resource could not be loaded."
        }
    }
}
