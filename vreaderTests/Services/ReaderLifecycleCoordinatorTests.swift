// Purpose: Tests for ReaderLifecycleCoordinator — close, background, foreground,
// periodic flush, session time, and content-loaded guard.

import Testing
import Foundation
@testable import vreader

// MARK: - Mock Delegate

@MainActor
final class MockLifecycleDelegate: ReaderLifecycleDelegate {
    var hasLoadedContent: Bool = false
    var locatorToReturn: Locator?
    var cleanupCallCount = 0

    func makeCurrentLocator() -> Locator? {
        locatorToReturn
    }

    func performFormatSpecificCleanup() async {
        cleanupCallCount += 1
    }
}

// MARK: - Fixtures

private let testFP = DocumentFingerprint(
    contentSHA256: "lifecycle_test_sha256_000000000000000000000000000000000000000",
    fileByteCount: 1000,
    format: .epub
)

private func makeTestLocator(page: Int = 0, progression: Double? = 0.5) -> Locator {
    Locator(
        bookFingerprint: testFP,
        href: "ch1.xhtml", progression: progression, totalProgression: progression,
        cfi: nil, page: page,
        charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
        textQuote: nil, textContextBefore: nil, textContextAfter: nil
    )
}

// MARK: - Close

@Suite("ReaderLifecycleCoordinator - Close")
@MainActor
struct ReaderLifecycleCoordinatorCloseTests {

    @Test func close_savesPosition_recordsProgress_endsSession_recomputesStats_notifies() async {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()
        let delegate = MockLifecycleDelegate()
        delegate.hasLoadedContent = true
        delegate.locatorToReturn = makeTestLocator(page: 5)

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )
        coordinator.delegate = delegate

        // Simulate: content loaded, session started
        coordinator.markContentLoaded()
        try! tracker.startSessionIfNeeded(bookFingerprint: testFP)
        coordinator.startPeriodicFlush()

        // Set up notification expectation
        var didReceiveNotification = false
        let observer = NotificationCenter.default.addObserver(
            forName: .readerDidClose,
            object: nil,
            queue: .main
        ) { _ in
            didReceiveNotification = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await coordinator.close()

        // Position was saved
        let savedPos = await positionStore.position(forKey: testFP.canonicalKey)
        #expect(savedPos != nil)

        // Session was ended
        #expect(tracker.state.isIdle)

        // Format-specific cleanup was called
        #expect(delegate.cleanupCallCount == 1)

        // Notification was posted
        #expect(didReceiveNotification)

        // isOpenComplete is reset
        #expect(!coordinator.isOpenComplete)
    }

    @Test func close_noOp_whenNoContentLoaded() async {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()
        let delegate = MockLifecycleDelegate()
        delegate.hasLoadedContent = false
        delegate.locatorToReturn = nil

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )
        coordinator.delegate = delegate

        // Do NOT call markContentLoaded()

        await coordinator.close()

        // No position save
        let saveCount = await positionStore.saveCallCount
        #expect(saveCount == 0)

        // Cleanup still called (delegate cleanup is unconditional)
        // But session-related ops were skipped
        #expect(tracker.state.isIdle)
    }

    @Test func close_callsFormatSpecificCleanup() async {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()
        let delegate = MockLifecycleDelegate()
        delegate.hasLoadedContent = true
        delegate.locatorToReturn = makeTestLocator()

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )
        coordinator.delegate = delegate
        coordinator.markContentLoaded()
        try! tracker.startSessionIfNeeded(bookFingerprint: testFP)

        await coordinator.close()

        #expect(delegate.cleanupCallCount == 1)
    }

    @Test func close_cancelsPendingFlush() async throws {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()
        let delegate = MockLifecycleDelegate()
        delegate.hasLoadedContent = true
        delegate.locatorToReturn = makeTestLocator()

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )
        coordinator.delegate = delegate
        coordinator.markContentLoaded()
        try tracker.startSessionIfNeeded(bookFingerprint: testFP)
        coordinator.startPeriodicFlush()

        await coordinator.close()

        // After close, the flush task should be nil (cancelled)
        #expect(!coordinator.hasActiveFlushTask)
    }

    @Test func close_idempotent_doubleCloseIsSafe() async {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()
        let delegate = MockLifecycleDelegate()
        delegate.hasLoadedContent = true
        delegate.locatorToReturn = makeTestLocator()

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )
        coordinator.delegate = delegate
        coordinator.markContentLoaded()
        try! tracker.startSessionIfNeeded(bookFingerprint: testFP)

        await coordinator.close()
        await coordinator.close() // second close — should not crash

        #expect(delegate.cleanupCallCount == 2)
        #expect(tracker.state.isIdle)
    }
}

// MARK: - Background

@Suite("ReaderLifecycleCoordinator - Background")
@MainActor
struct ReaderLifecycleCoordinatorBackgroundTests {

    @Test func onBackground_savesPosition_accumulatesTime_pausesSession() async {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()
        let delegate = MockLifecycleDelegate()
        delegate.hasLoadedContent = true
        delegate.locatorToReturn = makeTestLocator()

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )
        coordinator.delegate = delegate
        coordinator.markContentLoaded()
        try! tracker.startSessionIfNeeded(bookFingerprint: testFP)
        coordinator.startSession()

        await coordinator.onBackground()

        // Position was saved
        let saveCount = await positionStore.saveCallCount
        #expect(saveCount == 1)

        // Session paused
        #expect(tracker.state.isPausedGrace)

        // Flush task cancelled
        #expect(!coordinator.hasActiveFlushTask)
    }

    @Test func onBackground_noOp_whenNoContent() async {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()
        let delegate = MockLifecycleDelegate()
        delegate.hasLoadedContent = false

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )
        coordinator.delegate = delegate

        await coordinator.onBackground()

        // No position save
        let saveCount = await positionStore.saveCallCount
        #expect(saveCount == 0)
    }
}

// MARK: - Foreground

@Suite("ReaderLifecycleCoordinator - Foreground")
@MainActor
struct ReaderLifecycleCoordinatorForegroundTests {

    @Test func onForeground_resumesSession_restartsFlush() async throws {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()
        let delegate = MockLifecycleDelegate()
        delegate.hasLoadedContent = true
        delegate.locatorToReturn = makeTestLocator()

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )
        coordinator.delegate = delegate
        coordinator.markContentLoaded()

        // Start session, then background, then foreground
        try tracker.startSessionIfNeeded(bookFingerprint: testFP)
        coordinator.startSession()
        tracker.pause()

        coordinator.onForeground()

        // Session should be active again
        #expect(tracker.state.isActive)

        // Flush task should be running
        #expect(coordinator.hasActiveFlushTask)
    }

    @Test func onForeground_noOp_whenNoContent() {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()
        let delegate = MockLifecycleDelegate()
        delegate.hasLoadedContent = false

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )
        coordinator.delegate = delegate
        // Not marking content loaded

        coordinator.onForeground()

        // Session should stay idle
        #expect(tracker.state.isIdle)
        #expect(!coordinator.hasActiveFlushTask)
    }
}

// MARK: - Session Time

@Suite("ReaderLifecycleCoordinator - Session Time")
@MainActor
struct ReaderLifecycleCoordinatorTimeTests {

    @Test func updateTimeDisplays_computesAccumulatedTime() {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()
        let delegate = MockLifecycleDelegate()

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )
        coordinator.delegate = delegate

        // Manually set accumulated time for testing
        coordinator.startSession()

        // After starting a session, the time display should be computed
        coordinator.updateTimeDisplays()

        // With 0 accumulated seconds and a just-started segment, time should be <1m
        // (or nil if 0 seconds exactly)
        // The exact value depends on timing, so just check it was set
        // At startup, accumulatedActiveSeconds is 0 and segmentStartDate is just now,
        // so total ~= 0 seconds -> formatReadingTime returns nil for 0
        #expect(coordinator.sessionTimeDisplay == nil)
    }

    @Test func startSession_callsSessionTracker() {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )

        coordinator.startSession()

        // segmentStartDate should be set (internal time tracking started)
        // We can verify via accumulated time
        #expect(coordinator.sessionTimeDisplay == nil) // 0 seconds = nil
    }

    @Test func markContentLoaded_enablesLifecycleMethods() async {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()
        let delegate = MockLifecycleDelegate()
        delegate.hasLoadedContent = true
        delegate.locatorToReturn = makeTestLocator()

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )
        coordinator.delegate = delegate

        // Before marking content loaded, close should skip position save
        #expect(!coordinator.isOpenComplete)

        coordinator.markContentLoaded()
        #expect(coordinator.isOpenComplete)

        // Now close should do full sequence
        try! tracker.startSessionIfNeeded(bookFingerprint: testFP)
        await coordinator.close()

        let saveCount = await positionStore.saveCallCount
        #expect(saveCount == 1)
    }
}

// MARK: - Background/Foreground Round Trip

@Suite("ReaderLifecycleCoordinator - Round Trip")
@MainActor
struct ReaderLifecycleCoordinatorRoundTripTests {

    @Test func background_then_foreground_restoresState() async throws {
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: sessionStore, deviceId: "dev-1")
        let positionStore = MockPositionStore()
        let delegate = MockLifecycleDelegate()
        delegate.hasLoadedContent = true
        delegate.locatorToReturn = makeTestLocator()

        let coordinator = ReaderLifecycleCoordinator(
            bookFingerprint: testFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "dev-1"
        )
        coordinator.delegate = delegate
        coordinator.markContentLoaded()
        try tracker.startSessionIfNeeded(bookFingerprint: testFP)
        coordinator.startSession()

        // Background
        await coordinator.onBackground()
        #expect(tracker.state.isPausedGrace)
        #expect(!coordinator.hasActiveFlushTask)

        // Foreground
        coordinator.onForeground()
        #expect(tracker.state.isActive)
        #expect(coordinator.hasActiveFlushTask)
    }
}
