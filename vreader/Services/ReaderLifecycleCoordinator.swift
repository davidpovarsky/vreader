// Purpose: Shared reader lifecycle coordinator for close/background/foreground/session.
// Extracts the duplicated lifecycle logic from EPUB/PDF/TXT/MD ViewModels.
// Phase 0: standalone coordinator + tests. VMs are NOT wired yet (follow-up step).
//
// Key decisions:
// - @MainActor isolation — matches all reader VMs.
// - Delegate pattern for format-specific behavior (locator, cleanup).
// - Owns: periodic flush task, accumulated time, isOpenComplete flag.
// - Does NOT own: position service (created per-book, passed to close/onBackground).
// - close() order is load-bearing (bugs #34, #45): saveNow → recordProgress → end → stats → notify → cleanup.
//
// @coordinates-with: ReaderPositionService.swift, ReadingSessionTracker.swift,
//   ReadingPositionPersisting.swift, PersistenceActor+Stats.swift

import Foundation

// MARK: - Delegate Protocol

/// Format-specific behavior that the coordinator delegates back to the ViewModel.
@MainActor
protocol ReaderLifecycleDelegate: AnyObject {
    /// Whether the reader has loaded content (file decoded, metadata parsed, etc.).
    var hasLoadedContent: Bool { get }

    /// Creates a Locator representing the current reading position.
    /// Returns nil if no meaningful position exists.
    func makeCurrentLocator() -> Locator?

    /// Performs format-specific cleanup (e.g., close parser, close service).
    func performFormatSpecificCleanup() async
}

// MARK: - Coordinator

/// Shared lifecycle coordinator for reader close/background/foreground/session management.
///
/// Thread safety: @MainActor-isolated (UI-driven lifecycle).
@MainActor
final class ReaderLifecycleCoordinator {

    // MARK: - Constants

    /// Periodic flush interval for session duration (seconds).
    static let sessionFlushInterval: TimeInterval = 60.0

    // MARK: - Public State

    /// Formatted session reading time (e.g., "5m").
    private(set) var sessionTimeDisplay: String?

    /// True after open() completes position restore. Guards close() from saving
    /// stale position 0 when close() races with an in-progress open().
    private(set) var isOpenComplete = false

    /// Whether the periodic flush task is currently running.
    var hasActiveFlushTask: Bool { flushTask != nil }

    // MARK: - Dependencies

    let bookFingerprint: DocumentFingerprint
    let bookFingerprintKey: String
    private let positionStore: any ReadingPositionPersisting
    private let sessionTracker: ReadingSessionTracker
    private let positionService: ReaderPositionService

    /// Weak delegate for format-specific behavior.
    weak var delegate: (any ReaderLifecycleDelegate)?

    // MARK: - Private State

    private var flushTask: Task<Void, Never>?
    /// Date when the current active segment started (reset on resume).
    private var segmentStartDate: Date?
    /// Accumulated active reading seconds (excluding paused time).
    private var accumulatedActiveSeconds: TimeInterval = 0

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        positionStore: any ReadingPositionPersisting,
        sessionTracker: ReadingSessionTracker,
        deviceId: String,
        positionSaveDebounceNs: UInt64 = 2_000_000_000
    ) {
        self.bookFingerprint = bookFingerprint
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.positionStore = positionStore
        self.sessionTracker = sessionTracker
        self.positionService = ReaderPositionService(
            bookFingerprintKey: bookFingerprint.canonicalKey,
            deviceId: deviceId,
            persistence: positionStore,
            debounceNanoseconds: positionSaveDebounceNs
        )
    }

    // MARK: - Content Loaded

    /// Marks content as loaded. Call after open() completes position restore.
    /// Enables close() to save position and record progress.
    func markContentLoaded() {
        isOpenComplete = true
    }

    // MARK: - Session Start

    /// Initializes session time tracking. Call after sessionTracker.startSessionIfNeeded.
    func startSession() {
        segmentStartDate = Date()
        accumulatedActiveSeconds = 0
    }

    // MARK: - Lifecycle: Close

    /// Closes the reader, ending the session and flushing state.
    /// Order is load-bearing (bugs #34, #45): saveNow → recordProgress → end → stats → notify → cleanup.
    func close() async {
        flushTask?.cancel()
        flushTask = nil

        if isOpenComplete, let delegate, delegate.hasLoadedContent {
            if let locator = delegate.makeCurrentLocator() {
                await positionService.saveNow(locator: locator)
                sessionTracker.recordProgress(locator: locator)
            }
        }

        sessionTracker.endSessionIfNeeded()

        if let persistence = positionStore as? PersistenceActor {
            try? await persistence.recomputeStats(
                bookFingerprintKey: bookFingerprintKey,
                bookFingerprint: bookFingerprint
            )
        }

        NotificationCenter.default.post(name: .readerDidClose, object: bookFingerprintKey)

        await delegate?.performFormatSpecificCleanup()

        resetState()
    }

    // MARK: - Lifecycle: Background

    /// Called when the app moves to background while reader is open.
    /// Awaits the position save to guarantee it completes before iOS suspends.
    /// Guards on isOpenComplete to avoid persisting a stale pre-restore locator
    /// if the app backgrounds during open/restore (same guard as close()).
    func onBackground() async {
        guard isOpenComplete else { return }

        if let delegate, delegate.hasLoadedContent {
            if let locator = delegate.makeCurrentLocator() {
                await positionService.saveNow(locator: locator)
            }
        }

        if let start = segmentStartDate {
            accumulatedActiveSeconds += Date().timeIntervalSince(start)
            segmentStartDate = nil
        }

        sessionTracker.pause()
        flushTask?.cancel()
        flushTask = nil
    }

    // MARK: - Lifecycle: Foreground

    /// Called when the app returns to foreground with reader open.
    func onForeground() {
        guard let delegate, delegate.hasLoadedContent else { return }
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            // Non-fatal — session resume failure should not block reading
            return
        }
        if segmentStartDate == nil { segmentStartDate = Date() }
        startPeriodicFlush()
    }

    // MARK: - Periodic Flush

    /// Starts the periodic session flush timer. Cancels any existing timer first.
    func startPeriodicFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.sessionFlushInterval))
                    guard let self else { break }
                    try self.sessionTracker.periodicFlush()
                    self.updateTimeDisplays()
                } catch is CancellationError {
                    break
                } catch {
                    // Non-fatal
                }
            }
        }
    }

    // MARK: - Time Display

    /// Updates the session time display from accumulated active seconds.
    func updateTimeDisplays() {
        var total = accumulatedActiveSeconds
        if let start = segmentStartDate {
            total += Date().timeIntervalSince(start)
        }
        let sessionSeconds = Int(total)
        sessionTimeDisplay = ReadingTimeFormatter.formatReadingTime(totalSeconds: sessionSeconds)
    }

    // MARK: - Position Save (passthrough)

    /// Schedules a debounced position save.
    func scheduleSave(locator: Locator) {
        positionService.scheduleSave(locator: locator)
    }

    /// Saves position immediately.
    func saveNow(locator: Locator) async {
        await positionService.saveNow(locator: locator)
    }

    // MARK: - Private

    private func resetState() {
        segmentStartDate = nil
        accumulatedActiveSeconds = 0
        sessionTimeDisplay = nil
        isOpenComplete = false
    }
}
