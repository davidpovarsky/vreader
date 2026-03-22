// Purpose: RED tests for Bug #77 — Cannot add highlight in native EPUB.
// Proves the root cause: EPUBHighlightRenderer silently drops JS when onInjectJS
// is nil (race between .task callback setup and highlight creation), and the
// restoreHighlightsOnLoad callback swap can lose concurrent highlight JS.
//
// These tests assert CORRECT behavior that the current code does NOT implement.
// They should FAIL until the bug is fixed.
//
// @coordinates-with: EPUBHighlightRenderer.swift, HighlightCoordinator.swift,
//   EPUBReaderContainerView+Highlights.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

// MARK: - Test Helpers

private let testFP77 = DocumentFingerprint(
    contentSHA256: "bug77_test_sha256_000000000000000000000000000000000000000",
    fileByteCount: 500,
    format: .epub
)

private func makeEPUBLocator() -> Locator {
    Locator(
        bookFingerprint: testFP77,
        href: "chapter1.xhtml", progression: 0.5, totalProgression: 0.1,
        cfi: "", page: nil, charOffsetUTF16: nil,
        charRangeStartUTF16: nil, charRangeEndUTF16: nil,
        textQuote: "test text", textContextBefore: nil, textContextAfter: nil
    )
}

private func makeEPUBRecord(id: UUID = UUID()) -> HighlightRecord {
    let range = EPUBSerializedRange(
        startContainerPath: "/html/body/p[1]/text()",
        startOffset: 0,
        endContainerPath: "/html/body/p[1]/text()",
        endOffset: 10
    )
    return HighlightRecord(
        highlightId: id,
        locator: makeEPUBLocator(),
        anchor: .epub(href: "chapter1.xhtml", cfi: "", serializedRange: range),
        profileKey: "epub:sha:500",
        selectedText: "test text",
        color: "yellow",
        note: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
}

@MainActor
private final class MockPersistence77: HighlightPersisting, @unchecked Sendable {
    var stubbedHighlights: [HighlightRecord] = []

    func addHighlight(
        locator: Locator, selectedText: String, color: String,
        note: String?, toBookWithKey key: String
    ) async throws -> HighlightRecord {
        try await addHighlight(
            locator: locator, anchor: nil, selectedText: selectedText,
            color: color, note: note, toBookWithKey: key
        )
    }

    func addHighlight(
        locator: Locator, anchor: AnnotationAnchor?, selectedText: String,
        color: String, note: String?, toBookWithKey key: String
    ) async throws -> HighlightRecord {
        makeEPUBRecord()
    }

    func removeHighlight(highlightId: UUID) async throws {}
    func updateHighlightNote(highlightId: UUID, note: String?) async throws {}
    func updateHighlightColor(highlightId: UUID, color: String) async throws {}

    func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] {
        stubbedHighlights
    }
}

// MARK: - Bug #77 Tests

@Suite("Bug #77 — EPUB Highlight Renderer")
@MainActor
struct EPUBHighlightRendererBug77Tests {

    // -----------------------------------------------------------------------
    // ROOT CAUSE TEST: onInjectJS nil → JS silently lost
    // -----------------------------------------------------------------------

    @Test("apply() should not silently lose JS when onInjectJS is nil")
    func applyWithNilCallback_shouldNotLoseJS() {
        let renderer = EPUBHighlightRenderer()
        // onInjectJS is nil (simulates race: .task hasn't set it yet)

        let record = makeEPUBRecord()
        renderer.apply(record: record)

        // After onInjectJS is set (simulating .task completing), the lost JS
        // should be delivered. We capture it to verify.
        var deliveredJS: [String] = []
        renderer.onInjectJS = { js in
            deliveredJS.append(js)
        }

        // BUG: The JS from the apply() call was lost. It was never queued.
        // Correct behavior: renderer should buffer pending JS and flush
        // when onInjectJS becomes available.
        #expect(!deliveredJS.isEmpty,
                "JS from apply() while onInjectJS was nil should be delivered when callback is set")
    }

    @Test("remove() should not silently lose JS when onInjectJS is nil")
    func removeWithNilCallback_shouldNotLoseJS() {
        let renderer = EPUBHighlightRenderer()
        // onInjectJS is nil

        renderer.remove(id: UUID())

        var deliveredJS: [String] = []
        renderer.onInjectJS = { js in
            deliveredJS.append(js)
        }

        // BUG: Same as apply — remove JS is lost when callback is nil
        #expect(!deliveredJS.isEmpty,
                "JS from remove() while onInjectJS was nil should be delivered when callback is set")
    }

    // -----------------------------------------------------------------------
    // RACE CONDITION: restoreHighlightsOnLoad callback swap
    // -----------------------------------------------------------------------

    @Test("highlight created during restore should be delivered to correct callback")
    func highlightDuringRestore_shouldNotBeMisdirected() async {
        let renderer = EPUBHighlightRenderer()
        renderer.currentHref = "chapter1.xhtml"
        let persistence = MockPersistence77()
        persistence.stubbedHighlights = [makeEPUBRecord()]

        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )

        // Simulate the normal callback (writes to pendingHighlightJS state)
        var pendingJS: [String] = []
        let normalCallback: (String) -> Void = { js in pendingJS.append(js) }
        renderer.onInjectJS = normalCallback

        // Simulate restoreHighlightsOnLoad's callback swap pattern:
        // 1. Save original
        let original = renderer.onInjectJS
        // 2. Replace with page-ready evaluator
        var pageEvalJS: [String] = []
        renderer.onInjectJS = { js in pageEvalJS.append(js) }

        // 3. While restore is running, a NEW highlight is created
        //    (user taps "Highlight" in confirmation dialog)
        let newRecord = await coordinator.create(
            locator: makeEPUBLocator(),
            selectedText: "new highlight"
        )

        // 4. Restore original callback
        renderer.onInjectJS = original

        // The new highlight's JS was sent to pageEvalJS (the restore callback)
        // instead of pendingJS (the normal state-update callback).
        // BUG: The new highlight JS should have gone to the normal callback.
        #expect(newRecord != nil)
        #expect(!pendingJS.isEmpty,
                "New highlight JS should be delivered to the normal callback, not the temporary restore callback")
    }

    // -----------------------------------------------------------------------
    // COORDINATOR AVAILABILITY
    // -----------------------------------------------------------------------

    @Test("coordinator create + apply should deliver JS end-to-end")
    func coordinatorCreateDeliversJS() async {
        let renderer = EPUBHighlightRenderer()
        let persistence = MockPersistence77()
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )

        var deliveredJS: [String] = []
        renderer.onInjectJS = { js in deliveredJS.append(js) }

        let record = await coordinator.create(
            locator: makeEPUBLocator(),
            anchor: .epub(
                href: "chapter1.xhtml",
                cfi: "",
                serializedRange: EPUBSerializedRange(
                    startContainerPath: "/html/body/p[1]/text()",
                    startOffset: 0,
                    endContainerPath: "/html/body/p[1]/text()",
                    endOffset: 10
                )
            ),
            selectedText: "test text"
        )

        #expect(record != nil)
        // This should pass — verifies the happy path works
        #expect(!deliveredJS.isEmpty,
                "Coordinator create → renderer apply should deliver JS to callback")
    }
}
#endif
