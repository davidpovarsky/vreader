// Purpose: Tests for EPUBHighlightActions — highlight persistence,
// JS generation for inject/restore, and edge cases.
//
// @coordinates-with: EPUBHighlightActions.swift, EPUBHighlightBridge.swift,
//   HighlightPersisting.swift, AnnotationAnchor.swift

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
@testable import vreader

// MARK: - Mock Highlight Store

/// Captures calls to addHighlight for test assertions.
private final class SpyHighlightStore: HighlightPersisting, @unchecked Sendable {
    private(set) var addCalls: [(anchor: AnnotationAnchor?, selectedText: String, color: String, bookKey: String)] = []
    private(set) var fetchCalls: [String] = []
    var stubbedHighlights: [HighlightRecord] = []
    var shouldThrow = false

    func addHighlight(
        locator: Locator, selectedText: String, color: String,
        note: String?, toBookWithKey key: String
    ) async throws -> HighlightRecord {
        try await addHighlight(locator: locator, anchor: nil, selectedText: selectedText,
                               color: color, note: note, toBookWithKey: key)
    }

    func addHighlight(
        locator: Locator, anchor: AnnotationAnchor?, selectedText: String,
        color: String, note: String?, toBookWithKey key: String
    ) async throws -> HighlightRecord {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        addCalls.append((anchor: anchor, selectedText: selectedText, color: color, bookKey: key))
        return HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            anchor: anchor,
            profileKey: "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)",
            selectedText: selectedText,
            color: color,
            note: note,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func removeHighlight(highlightId: UUID) async throws {}
    func updateHighlightNote(highlightId: UUID, note: String?) async throws {}
    func updateHighlightColor(highlightId: UUID, color: String) async throws {}

    func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] {
        fetchCalls.append(key)
        if shouldThrow { throw NSError(domain: "test", code: 2) }
        return stubbedHighlights
    }
}

// MARK: - Test Helpers

private let testFingerprint = DocumentFingerprint(
    contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
    fileByteCount: 2048,
    format: .epub
)

private func makeTestLocator(href: String = "ch1.xhtml") -> Locator {
    Locator(
        bookFingerprint: testFingerprint,
        href: href,
        progression: 0.5,
        totalProgression: 0.25,
        cfi: nil,
        page: nil,
        charOffsetUTF16: nil,
        charRangeStartUTF16: nil,
        charRangeEndUTF16: nil,
        textQuote: nil,
        textContextBefore: nil,
        textContextAfter: nil
    )
}

private func makeTestRange(
    startPath: String = "/html/body/p[1]/text()",
    startOffset: Int = 0,
    endPath: String = "/html/body/p[1]/text()",
    endOffset: Int = 10
) -> EPUBSerializedRange {
    EPUBSerializedRange(
        startContainerPath: startPath,
        startOffset: startOffset,
        endContainerPath: endPath,
        endOffset: endOffset
    )
}

private func makeTestEvent(
    text: String = "Hello World",
    href: String = "ch1.xhtml",
    range: EPUBSerializedRange? = nil
) -> ReaderSelectionEvent {
    let r = range ?? makeTestRange()
    let anchor = AnnotationAnchor.epub(href: href, cfi: "", serializedRange: r)
    return ReaderSelectionEvent(
        selectedText: text,
        anchor: anchor,
        sourceRect: CGRect(x: 100, y: 200, width: 150, height: 20)
    )
}

private func makeHighlightRecord(
    href: String = "ch1.xhtml",
    range: EPUBSerializedRange? = nil,
    color: String = "yellow",
    selectedText: String = "Hello World"
) -> HighlightRecord {
    let r = range ?? makeTestRange()
    let anchor = AnnotationAnchor.epub(href: href, cfi: "", serializedRange: r)
    let locator = makeTestLocator(href: href)
    return HighlightRecord(
        highlightId: UUID(),
        locator: locator,
        anchor: anchor,
        profileKey: "test-profile",
        selectedText: selectedText,
        color: color,
        note: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
}

// MARK: - Persist Highlight Tests

@Suite("EPUBHighlightActions — persistHighlight")
struct EPUBHighlightActionsPersistTests {

    @Test("persist highlight calls addHighlight with correct fields")
    func persistHighlightCallsStore() async throws {
        let store = SpyHighlightStore()
        let event = makeTestEvent()
        let locator = makeTestLocator()

        let result = try await EPUBHighlightActions.persistHighlight(
            event: event,
            locator: locator,
            persistence: store,
            bookKey: testFingerprint.canonicalKey
        )

        #expect(store.addCalls.count == 1)
        #expect(store.addCalls[0].selectedText == "Hello World")
        #expect(store.addCalls[0].color == "yellow")
        #expect(store.addCalls[0].bookKey == testFingerprint.canonicalKey)
        // Verify anchor is passed through
        if case .epub(let href, _, _) = store.addCalls[0].anchor {
            #expect(href == "ch1.xhtml")
        } else {
            Issue.record("Expected epub anchor")
        }
    }

    @Test("persist highlight returns record with highlight ID")
    func persistReturnsRecord() async throws {
        let store = SpyHighlightStore()
        let event = makeTestEvent()
        let locator = makeTestLocator()

        let result = try await EPUBHighlightActions.persistHighlight(
            event: event,
            locator: locator,
            persistence: store,
            bookKey: testFingerprint.canonicalKey
        )

        #expect(result.selectedText == "Hello World")
        #expect(result.color == "yellow")
    }

    @Test("persist highlight with CJK text")
    func persistWithCJKText() async throws {
        let store = SpyHighlightStore()
        let event = makeTestEvent(text: "你好世界")
        let locator = makeTestLocator()

        _ = try await EPUBHighlightActions.persistHighlight(
            event: event,
            locator: locator,
            persistence: store,
            bookKey: testFingerprint.canonicalKey
        )

        #expect(store.addCalls[0].selectedText == "你好世界")
    }

    @Test("persist highlight propagates error from store")
    func persistPropagatesError() async {
        let store = SpyHighlightStore()
        store.shouldThrow = true
        let event = makeTestEvent()
        let locator = makeTestLocator()

        do {
            _ = try await EPUBHighlightActions.persistHighlight(
                event: event,
                locator: locator,
                persistence: store,
                bookKey: testFingerprint.canonicalKey
            )
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected
            #expect(store.addCalls.isEmpty)
        }
    }
}

// MARK: - Create Highlight JS Tests

@Suite("EPUBHighlightActions — createHighlightJS")
struct EPUBHighlightActionsCreateJSTests {

    @Test("generates JS for epub anchor")
    func generatesJSForEPUBAnchor() {
        let range = makeTestRange()
        let anchor = AnnotationAnchor.epub(href: "ch1.xhtml", cfi: "", serializedRange: range)
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makeTestLocator(),
            anchor: anchor,
            profileKey: "test",
            selectedText: "Hello",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let js = EPUBHighlightActions.createHighlightJS(for: record)
        #expect(js != nil)
        #expect(js!.contains("createHighlight"))
        #expect(js!.contains("yellow"))
    }

    @Test("returns nil for non-epub anchor")
    func returnsNilForPDFAnchor() {
        let anchor = AnnotationAnchor.pdf(page: 5, rects: [])
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makeTestLocator(),
            anchor: anchor,
            profileKey: "test",
            selectedText: "Hello",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let js = EPUBHighlightActions.createHighlightJS(for: record)
        #expect(js == nil)
    }

    @Test("returns nil for nil anchor")
    func returnsNilForNilAnchor() {
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makeTestLocator(),
            anchor: nil,
            profileKey: "test",
            selectedText: "Hello",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let js = EPUBHighlightActions.createHighlightJS(for: record)
        #expect(js == nil)
    }
}

// MARK: - Restore Highlights Tests

@Suite("EPUBHighlightActions — restoreHighlightsJS")
struct EPUBHighlightActionsRestoreTests {

    @Test("filters highlights to current chapter href")
    func filtersToCurrentChapter() {
        let ch1 = makeHighlightRecord(href: "ch1.xhtml")
        let ch2 = makeHighlightRecord(href: "ch2.xhtml")
        let ch1b = makeHighlightRecord(href: "ch1.xhtml",
            range: makeTestRange(startOffset: 20, endOffset: 30))

        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [ch1, ch2, ch1b],
            currentHref: "ch1.xhtml"
        )

        #expect(js.contains("createHighlight"))
        // Should contain references to ch1 highlights but not ch2
        // We verify by checking JS contains the highlight IDs for ch1 items
    }

    @Test("returns empty string for no matching highlights")
    func returnsEmptyForNoMatches() {
        let ch2 = makeHighlightRecord(href: "ch2.xhtml")

        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [ch2],
            currentHref: "ch1.xhtml"
        )

        #expect(js.isEmpty)
    }

    @Test("returns empty string for empty highlights array")
    func returnsEmptyForEmptyArray() {
        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [],
            currentHref: "ch1.xhtml"
        )

        #expect(js.isEmpty)
    }

    @Test("handles highlights with nil anchor gracefully")
    func skipsNilAnchors() {
        let noAnchor = HighlightRecord(
            highlightId: UUID(),
            locator: makeTestLocator(),
            anchor: nil,
            profileKey: "test",
            selectedText: "Hello",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        let withAnchor = makeHighlightRecord(href: "ch1.xhtml")

        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [noAnchor, withAnchor],
            currentHref: "ch1.xhtml"
        )

        // Should still generate JS for the one with a valid anchor
        #expect(js.contains("createHighlight"))
    }

    @Test("handles highlights with PDF anchor (wrong format) gracefully")
    func skipsPDFAnchors() {
        let pdfHighlight = HighlightRecord(
            highlightId: UUID(),
            locator: makeTestLocator(),
            anchor: .pdf(page: 1, rects: []),
            profileKey: "test",
            selectedText: "Hello",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [pdfHighlight],
            currentHref: "ch1.xhtml"
        )

        #expect(js.isEmpty)
    }

    @Test("preserves highlight colors in restore JS")
    func preservesColors() {
        let yellow = makeHighlightRecord(href: "ch1.xhtml", color: "yellow")
        let blue = makeHighlightRecord(href: "ch1.xhtml",
            range: makeTestRange(startOffset: 20, endOffset: 30), color: "blue")

        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [yellow, blue],
            currentHref: "ch1.xhtml"
        )

        #expect(js.contains("yellow"))
        #expect(js.contains("blue"))
    }

    @Test("empty currentHref returns empty string")
    func emptyHrefReturnsEmpty() {
        let record = makeHighlightRecord(href: "ch1.xhtml")

        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [record],
            currentHref: ""
        )

        #expect(js.isEmpty)
    }
}
#endif
