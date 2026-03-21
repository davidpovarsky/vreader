// Purpose: Shared lifecycle logic for reader ViewModels (Phase R6).
// Extracts duplicated session tracking, position save, stats recompute,
// and periodic flush from TXT/MD/EPUB/PDF ViewModels.
//
// Key decisions:
// - Composition (has-a) rather than inheritance — each VM owns a helper instance.
// - Format-specific details (locator construction, content-loaded check) are NOT
//   in the helper. The VM passes the locator to close/onBackground/recordProgress.
// - Owns the shared state: flushTask, segmentStartDate, accumulatedActiveSeconds,
//   sessionTimeDisplay.
// - Adding a new lifecycle hook (e.g., iCloud sync on close) touches this file only.
//
// @coordinates-with: TXTReaderViewModel.swift, MDReaderViewModel.swift,
//   EPUBReaderViewModel.swift, PDFReaderViewModel.swift,
//   ReaderPositionService.swift, ReadingSessionTracker.swift

import Foundation

/// Shared lifecycle helper for reader ViewModels.
/// Manages session tracking, position save/restore, stats recomputation,
/// and periodic flush. Each format ViewModel composes one instance.
@MainActor
final class ReaderLifecycleHelper {

    // MARK: - Constants

    /// Periodic flush interval for session duration (seconds).
    static let sessionFlushInterval: TimeInterval = 60.0

    // MARK: - Observable State

    /// Formatted session reading time (e.g., "5m"). VMs expose this to the UI.
    private(set) var sessionTimeDisplay: String?

    // MARK: - Dependencies

    let bookFingerprintKey: String
    let bookFingerprint: DocumentFingerprint
    let positionService: ReaderPositionService
    let sessionTracker: ReadingSessionTracker
    private let positionStore: any ReadingPositionPersisting

    // MARK: - Private State

    private var flushTask: Task<Void, Never>?
    /// Date when the current active segment started (reset on background/resume).
    private var segmentStartDate: Date?
    /// Accumulated active reading seconds (excluding paused time).
    private var accumulatedActiveSeconds: TimeInterval = 0

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        positionService: ReaderPositionService,
        sessionTracker: ReadingSessionTracker,
        positionStore: any ReadingPositionPersisting
    ) {
        self.bookFingerprint = bookFingerprint
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.positionService = positionService
        self.sessionTracker = sessionTracker
        self.positionStore = positionStore
    }

    // MARK: - Session Begin

    /// Starts a reading session and initializes timing.
    /// Throws if session tracking fails (caller should handle rollback).
    func beginSession() throws {
        try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        segmentStartDate = Date()
        accumulatedActiveSeconds = 0
        startPeriodicFlush()
    }

    /// Updates the lastOpenedAt timestamp for this book (non-fatal on failure).
    func updateLastOpened() async {
        try? await positionStore.updateLastOpened(
            bookFingerprintKey: bookFingerprintKey,
            date: Date()
        )
    }

    // MARK: - Close

    /// Performs the shared close sequence.
    /// Order is load-bearing (bugs #34, #45): saveNow → recordProgress → end → stats → notify.
    /// - Parameter locator: The current position locator (format-specific, built by the VM).
    ///   Pass nil if no content was loaded (skips position save).
    func close(locator: Locator?) async {
        cancelFlush()

        if let locator {
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

        // Reset shared state so stale values don't leak into a subsequent open()
        segmentStartDate = nil
        accumulatedActiveSeconds = 0
        sessionTimeDisplay = nil
    }

    // MARK: - Background / Foreground

    /// Saves position and pauses the session when the app moves to background.
    /// - Parameter locator: The current position locator, or nil if no content loaded.
    func onBackground(locator: Locator?) async {
        if let locator {
            await positionService.saveNow(locator: locator)
        }

        if let start = segmentStartDate {
            accumulatedActiveSeconds += Date().timeIntervalSince(start)
            segmentStartDate = nil
        }

        sessionTracker.pause()
        cancelFlush()
    }

    /// Resumes the session when the app returns to foreground.
    /// - Parameter alwaysResetSegment: When true, unconditionally resets segmentStartDate
    ///   (PDF behavior). When false, only sets it if nil (TXT/MD/EPUB behavior).
    /// Returns an error message if session resume fails, or nil on success.
    @discardableResult
    func onForeground(alwaysResetSegment: Bool = false) -> String? {
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            return "Failed to resume reading session."
        }
        if alwaysResetSegment {
            segmentStartDate = Date()
        } else if segmentStartDate == nil {
            segmentStartDate = Date()
        }
        startPeriodicFlush()
        return nil
    }

    // MARK: - Progress Tracking

    /// Records progress and schedules a position save.
    func recordProgressAndScheduleSave(locator: Locator) {
        sessionTracker.recordProgress(locator: locator)
        updateTimeDisplays()
        positionService.scheduleSave(locator: locator)
    }

    // MARK: - Time Display

    /// Updates sessionTimeDisplay from accumulated + current segment time.
    func updateTimeDisplays() {
        var total = accumulatedActiveSeconds
        if let start = segmentStartDate {
            total += Date().timeIntervalSince(start)
        }
        let sessionSeconds = Int(total)
        sessionTimeDisplay = ReadingTimeFormatter.formatReadingTime(totalSeconds: sessionSeconds)
    }

    /// Returns the total active seconds (accumulated + current segment).
    var totalActiveSeconds: TimeInterval {
        var total = accumulatedActiveSeconds
        if let start = segmentStartDate {
            total += Date().timeIntervalSince(start)
        }
        return total
    }

    // MARK: - Private

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

    private func cancelFlush() {
        flushTask?.cancel()
        flushTask = nil
    }
}
