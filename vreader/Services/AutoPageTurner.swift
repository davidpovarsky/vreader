// Purpose: Timer-based auto page turning for the reader.
// Calls navigator.nextPage() at a configurable interval.
// Stops at the last page. Pauses on user interaction.
//
// Key decisions:
// - @MainActor + @Observable for SwiftUI binding.
// - Interval clamped to 1...60 seconds.
// - Uses Task.sleep for timer to allow clean cancellation.
// - Auto-stops when navigator reaches last page.
//
// @coordinates-with PageNavigator.swift, BasePageNavigator.swift

import Foundation

/// Timer-based auto page turning service.
@MainActor @Observable
final class AutoPageTurner {

    // MARK: - Types

    enum State: Sendable, Equatable {
        case idle
        case running
        case paused
    }

    // MARK: - Public State

    private(set) var state: State = .idle

    /// Seconds between page turns, clamped to 1...60.
    var interval: TimeInterval = 5.0 {
        didSet { interval = Self.clampInterval(interval) }
    }

    // MARK: - Private

    private var timerTask: Task<Void, Never>?
    private weak var navigator: (any PageNavigator)?

    // MARK: - Public API

    /// Start auto page turning using the given navigator.
    /// If already running, restarts with the current interval.
    func start(navigator: any PageNavigator) {
        stop()
        self.navigator = navigator
        state = .running
        scheduleTimer()
    }

    /// Pause auto page turning. Timer is suspended but state is retained.
    func pause() {
        guard state == .running else { return }
        timerTask?.cancel()
        timerTask = nil
        state = .paused
    }

    /// Resume auto page turning from paused state.
    func resume() {
        guard state == .paused else { return }
        state = .running
        scheduleTimer()
    }

    /// Stop auto page turning completely. Resets to idle.
    func stop() {
        timerTask?.cancel()
        timerTask = nil
        navigator = nil
        state = .idle
    }

    // MARK: - Private

    private func scheduleTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let sleepInterval = self.interval
                try? await Task.sleep(for: .seconds(sleepInterval))
                guard !Task.isCancelled else { return }

                guard let nav = self.navigator else {
                    self.stop()
                    return
                }

                // Check if at last page
                if nav.currentPage >= nav.totalPages - 1 {
                    self.stop()
                    return
                }

                nav.nextPage()
            }
        }
    }

    private static func clampInterval(_ value: TimeInterval) -> TimeInterval {
        max(1.0, min(60.0, value))
    }
}
