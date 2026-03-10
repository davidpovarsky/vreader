// Purpose: Tests for ReaderPositionService extracted in WI-006.
// Validates debounced save, immediate save, cancel, and interleaving.
//
// @coordinates-with ReaderPositionService.swift, ReadingPositionPersisting.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Test Helpers

private let testFP = DocumentFingerprint(
    contentSHA256: "pos_service_test_sha256_00000000000000000000000000000000000",
    fileByteCount: 200,
    format: .txt
)

private func makeLocator(offset: Int = 0) -> Locator {
    Locator(
        bookFingerprint: testFP,
        href: nil, progression: nil, totalProgression: nil, cfi: nil, page: nil,
        charOffsetUTF16: offset,
        charRangeStartUTF16: nil, charRangeEndUTF16: nil,
        textQuote: nil, textContextBefore: nil, textContextAfter: nil
    )
}

// MARK: - Tests

@Suite("ReaderPositionService")
struct ReaderPositionServiceTests {

    // MARK: - saveNow

    @Test @MainActor func saveNowCallsPersistenceImmediately() async {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 2_000_000_000
        )

        let locator = makeLocator(offset: 100)
        await service.saveNow(locator: locator)

        let count = await store.saveCallCount
        #expect(count == 1)
        let saved = await store.position(forKey: "test-key")
        #expect(saved?.charOffsetUTF16 == 100)
    }

    @Test @MainActor func saveNowIsAwaitableNotFireAndForget() async {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 0
        )

        // After await returns, the save must have completed
        await service.saveNow(locator: makeLocator(offset: 50))
        let count = await store.saveCallCount
        #expect(count == 1)
    }

    // MARK: - scheduleSave (zero debounce for determinism)

    @Test @MainActor func scheduleSaveWithZeroDebounceEventuallySaves() async throws {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 0
        )

        service.scheduleSave(locator: makeLocator(offset: 200))
        // Give the Task a chance to run
        try await Task.sleep(for: .milliseconds(50))

        let count = await store.saveCallCount
        #expect(count == 1)
    }

    @Test @MainActor func scheduleSaveCoalescesRapidCalls() async throws {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 100_000_000 // 100ms
        )

        // Rapid scheduling — only the last should persist
        service.scheduleSave(locator: makeLocator(offset: 10))
        service.scheduleSave(locator: makeLocator(offset: 20))
        service.scheduleSave(locator: makeLocator(offset: 30))

        try await Task.sleep(for: .milliseconds(200))

        let count = await store.saveCallCount
        #expect(count == 1)
        let saved = await store.position(forKey: "test-key")
        #expect(saved?.charOffsetUTF16 == 30)
    }

    // MARK: - cancel

    @Test @MainActor func cancelPreventsScheduledSave() async throws {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 100_000_000 // 100ms
        )

        service.scheduleSave(locator: makeLocator(offset: 300))
        service.cancel()

        try await Task.sleep(for: .milliseconds(200))

        let count = await store.saveCallCount
        #expect(count == 0)
    }

    @Test @MainActor func cancelDoesNotSuppressSubsequentSaveNow() async {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 100_000_000
        )

        service.scheduleSave(locator: makeLocator(offset: 10))
        service.cancel()
        await service.saveNow(locator: makeLocator(offset: 20))

        let count = await store.saveCallCount
        #expect(count == 1)
        let saved = await store.position(forKey: "test-key")
        #expect(saved?.charOffsetUTF16 == 20)
    }

    // MARK: - Interleaving (regression: bugs #24, #25, #34, #45)

    @Test @MainActor func saveNowAfterScheduleSaveAlwaysCompletes() async throws {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 500_000_000 // 500ms (long debounce)
        )

        // Schedule a debounced save, then immediately save a different position
        service.scheduleSave(locator: makeLocator(offset: 100))
        await service.saveNow(locator: makeLocator(offset: 200))

        // saveNow must have completed — the scheduled one should be cancelled
        let count = await store.saveCallCount
        #expect(count == 1)
        let saved = await store.position(forKey: "test-key")
        #expect(saved?.charOffsetUTF16 == 200)
    }

    // MARK: - deinit

    @Test @MainActor func deinitCancelsPendingTask() async throws {
        let store = MockPositionStore()

        // Create and immediately destroy
        do {
            let service = ReaderPositionService(
                bookFingerprintKey: "test-key",
                deviceId: "device-1",
                persistence: store,
                debounceNanoseconds: 500_000_000
            )
            service.scheduleSave(locator: makeLocator(offset: 999))
            // service goes out of scope here
        }

        try await Task.sleep(for: .milliseconds(100))

        let count = await store.saveCallCount
        #expect(count == 0)
    }
}
