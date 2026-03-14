// Purpose: Tests for haptic feedback on bookmark add.
// Validates that haptic fires on successful add, and does NOT fire on error.
//
// Note: handleBookmarkRequest currently only adds bookmarks — it does not
// implement toggle/remove. The remove path is handled by BookmarkListViewModel
// but not wired through ReaderNotificationHandlers. A future WI should add
// toggle semantics to handleBookmarkRequest if haptic on remove is desired.
//
// @coordinates-with HapticFeedback.swift, ReaderNotificationHandlers.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Mock Haptic Provider

/// Records haptic trigger calls for test verification.
@MainActor
private final class MockHapticProvider: HapticFeedbackProviding {
    private(set) var lightImpactCount = 0

    func triggerLightImpact() {
        lightImpactCount += 1
    }
}

// MARK: - Test Helpers

private let testFP = DocumentFingerprint(
    contentSHA256: "bookmark_feedback_test_sha256_000000000000000000000000000000",
    fileByteCount: 200,
    format: .txt
)

private func makeLocator() -> Locator {
    Locator(
        bookFingerprint: testFP,
        href: nil, progression: nil, totalProgression: nil, cfi: nil, page: nil,
        charOffsetUTF16: nil,
        charRangeStartUTF16: nil,
        charRangeEndUTF16: nil,
        textQuote: nil, textContextBefore: nil, textContextAfter: nil
    )
}

@MainActor
private func makeDeps(
    bookmarks: MockBookmarkStore = MockBookmarkStore(),
    haptic: HapticFeedbackProviding? = nil
) -> ReaderNotificationDeps {
    ReaderNotificationDeps(
        bookFingerprintKey: "feedback-test-key",
        bookFingerprint: testFP,
        bookmarkPersistence: bookmarks,
        highlightPersistence: MockHighlightStore(),
        annotationPersistence: MockAnnotationStore(),
        locatorFactory: { fp, start, end, _ in
            Locator.validated(bookFingerprint: fp, charRangeStartUTF16: start, charRangeEndUTF16: end)
        },
        sourceText: { "Hello World" },
        makeCurrentLocator: { makeLocator() },
        onNavigate: { _ in },
        hapticFeedback: haptic
    )
}

// MARK: - Tests

@Suite("BookmarkFeedback")
struct BookmarkFeedbackTests {

    @Test @MainActor func feedbackGeneratorFiredOnAdd() async {
        let haptic = MockHapticProvider()
        let deps = makeDeps(haptic: haptic)

        await ReaderNotificationHandlers.handleBookmarkRequest(deps: deps)

        #expect(haptic.lightImpactCount == 1, "Haptic should fire once on successful bookmark add")
    }

    // Note: handleBookmarkRequest only adds — it does not toggle/remove.
    // This test verifies haptic fires on add even when a bookmark already
    // exists for the same locator (duplicate add scenario).
    @Test @MainActor func feedbackGeneratorFiredOnAddWithPreExistingBookmark() async {
        let haptic = MockHapticProvider()
        let bookmarks = MockBookmarkStore()

        // Pre-seed a bookmark so the store already has one for this locator.
        let existingLocator = makeLocator()
        let existingRecord = BookmarkRecord(
            bookmarkId: UUID(),
            locator: existingLocator,
            profileKey: "\(existingLocator.bookFingerprint.canonicalKey):\(existingLocator.canonicalHash)",
            title: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        await bookmarks.seed(existingRecord, forBookWithKey: "feedback-test-key")

        let deps = makeDeps(bookmarks: bookmarks, haptic: haptic)

        // handleBookmarkRequest always adds — even with a pre-existing bookmark.
        await ReaderNotificationHandlers.handleBookmarkRequest(deps: deps)

        #expect(haptic.lightImpactCount == 1, "Haptic should fire on successful bookmark add even with pre-existing bookmark")
        let totalBookmarks = await bookmarks.allBookmarks()
        #expect(totalBookmarks.count == 2, "Store should contain the seeded bookmark plus the newly added one")
    }

    @Test @MainActor func noFeedbackOnError() async {
        let haptic = MockHapticProvider()
        let bookmarks = MockBookmarkStore()
        await bookmarks.setAddError(MockPersistenceError.intentional)
        let deps = makeDeps(bookmarks: bookmarks, haptic: haptic)

        await ReaderNotificationHandlers.handleBookmarkRequest(deps: deps)

        #expect(haptic.lightImpactCount == 0, "Haptic should NOT fire when bookmark add fails")
    }

    @Test @MainActor func noFeedbackWhenProviderIsNil() async {
        // Default deps with nil haptic — should not crash
        let deps = makeDeps(haptic: nil)

        await ReaderNotificationHandlers.handleBookmarkRequest(deps: deps)

        // No crash = pass. This covers the default no-haptic path.
    }

    @Test @MainActor func rapidRepeatedBookmarksFeedbackFiresEachTime() async {
        let haptic = MockHapticProvider()
        let deps = makeDeps(haptic: haptic)

        await ReaderNotificationHandlers.handleBookmarkRequest(deps: deps)
        await ReaderNotificationHandlers.handleBookmarkRequest(deps: deps)
        await ReaderNotificationHandlers.handleBookmarkRequest(deps: deps)

        #expect(haptic.lightImpactCount == 3, "Haptic should fire once per successful bookmark add")
    }
}

// MARK: - Mock Error

private enum MockPersistenceError: Error, Sendable {
    case intentional
}
