// Purpose: Debounced reading position persistence service.
// Encapsulates the save-position debounce pattern shared across all reader VMs.
// Extracted in WI-006 — service-only, no adopters until WI-008a–d.
//
// Key decisions:
// - @MainActor isolation — one instance per book open, owned by the VM.
// - scheduleSave debounces via Task.sleep; cancel cancels pending task.
// - saveNow is truly async and awaitable (not fire-and-forget).
// - saveNow cancels any pending debounced save to avoid stale overwrites.
// - deinit calls cancel() to prevent leaked tasks.
// - Does NOT construct locators (format-specific, stays in VM).
// - Does NOT handle session tracking (that's ReadingSessionTracker).
//
// @coordinates-with ReadingPositionPersisting.swift, PersistenceActor+ReadingPosition.swift

import Foundation

/// Debounced position save service for reader ViewModels.
@MainActor
final class ReaderPositionService {
    private let bookFingerprintKey: String
    private let deviceId: String
    private let persistence: any ReadingPositionPersisting
    private let debounceNanoseconds: UInt64

    private var debounceTask: Task<Void, Never>?
    /// Monotonic version counter to prevent stale debounced writes from overwriting saveNow.
    private var saveVersion: UInt64 = 0

    init(
        bookFingerprintKey: String,
        deviceId: String,
        persistence: any ReadingPositionPersisting,
        debounceNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.bookFingerprintKey = bookFingerprintKey
        self.deviceId = deviceId
        self.persistence = persistence
        self.debounceNanoseconds = debounceNanoseconds
    }

    deinit {
        debounceTask?.cancel()
    }

    // MARK: - Public API

    /// Schedules a debounced save. Rapid calls coalesce — only the last locator persists.
    func scheduleSave(locator: Locator) {
        saveVersion &+= 1
        let capturedVersion = saveVersion
        debounceTask?.cancel()
        debounceTask = Task { [weak self, bookFingerprintKey, deviceId, persistence, debounceNanoseconds] in
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                // Drop stale write if saveNow or another scheduleSave bumped the version
                guard !Task.isCancelled, self?.saveVersion == capturedVersion else { return }
                try await persistence.savePosition(
                    bookFingerprintKey: bookFingerprintKey,
                    locator: locator,
                    deviceId: deviceId
                )
            } catch is CancellationError {
                // Expected when debounce is reset or cancelled
            } catch {
                // Persistence errors are non-fatal — caller logs if needed
            }
        }
    }

    /// Saves immediately. Awaitable — returns only after persistence completes.
    /// Cancels any pending debounced save and bumps version to prevent stale overwrites.
    func saveNow(locator: Locator) async {
        saveVersion &+= 1
        debounceTask?.cancel()
        debounceTask = nil
        try? await persistence.savePosition(
            bookFingerprintKey: bookFingerprintKey,
            locator: locator,
            deviceId: deviceId
        )
    }

    /// Cancels any pending debounced save. Safe to call multiple times.
    func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
    }
}
