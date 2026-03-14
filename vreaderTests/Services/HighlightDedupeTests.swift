// Purpose: Tests for highlight deduplication logic — ensures different anchors
// on the same locator are NOT collapsed, while exact duplicates are deduped.
//
// @coordinates-with: MockHighlightStore.swift, PersistenceActor+Highlights.swift,
//   AnnotationAnchor.swift

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("HighlightDedupe")
struct HighlightDedupeTests {

    static let fp = DocumentFingerprint(
        contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        fileByteCount: 2048,
        format: .pdf
    )

    static let bookKey = fp.canonicalKey

    /// Locator for a PDF page — coarse, page-level only.
    static func pdfLocator(page: Int) -> Locator {
        Locator(
            bookFingerprint: fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: page,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    static let epubFp = DocumentFingerprint(
        contentSHA256: "1111111111111111111111111111111111111111111111111111111111111111",
        fileByteCount: 4096,
        format: .epub
    )
    static let epubBookKey = epubFp.canonicalKey

    static func epubLocator(href: String, progression: Double) -> Locator {
        Locator(
            bookFingerprint: epubFp,
            href: href, progression: progression, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    // MARK: - PDF: Different rects on same page → both persisted

    @Test func twoPdfHighlightsSamePageDifferentRects() async throws {
        let store = MockHighlightStore()
        let locator = Self.pdfLocator(page: 5)

        let anchor1 = AnnotationAnchor.pdf(
            page: 5,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]
        )
        let anchor2 = AnnotationAnchor.pdf(
            page: 5,
            rects: [CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.03)]
        )

        let r1 = try await store.addHighlight(
            locator: locator, anchor: anchor1,
            selectedText: "First passage", color: "yellow", note: nil,
            toBookWithKey: Self.bookKey
        )
        let r2 = try await store.addHighlight(
            locator: locator, anchor: anchor2,
            selectedText: "Second passage", color: "yellow", note: nil,
            toBookWithKey: Self.bookKey
        )

        // Different rects → must NOT dedupe
        #expect(r1.highlightId != r2.highlightId)

        let all = await store.allHighlights()
        #expect(all.count == 2)
    }

    // MARK: - EPUB: Different ranges in same chapter → both persisted

    @Test func twoEpubHighlightsSameChapterDifferentRanges() async throws {
        let store = MockHighlightStore()
        let locator = Self.epubLocator(href: "chapter1.xhtml", progression: 0.3)

        let anchor1 = AnnotationAnchor.epub(
            href: "chapter1.xhtml",
            cfi: "/6/4",
            serializedRange: EPUBSerializedRange(
                startContainerPath: "/html/body/p[1]/text()",
                startOffset: 0,
                endContainerPath: "/html/body/p[1]/text()",
                endOffset: 10
            )
        )
        let anchor2 = AnnotationAnchor.epub(
            href: "chapter1.xhtml",
            cfi: "/6/4",
            serializedRange: EPUBSerializedRange(
                startContainerPath: "/html/body/p[3]/text()",
                startOffset: 5,
                endContainerPath: "/html/body/p[3]/text()",
                endOffset: 25
            )
        )

        let r1 = try await store.addHighlight(
            locator: locator, anchor: anchor1,
            selectedText: "First selection", color: "blue", note: nil,
            toBookWithKey: Self.epubBookKey
        )
        let r2 = try await store.addHighlight(
            locator: locator, anchor: anchor2,
            selectedText: "Second selection", color: "blue", note: nil,
            toBookWithKey: Self.epubBookKey
        )

        // Different ranges → must NOT dedupe
        #expect(r1.highlightId != r2.highlightId)

        let all = await store.allHighlights()
        #expect(all.count == 2)
    }

    // MARK: - Exact same anchor → deduped

    @Test func exactSamePdfAnchorDedupes() async throws {
        let store = MockHighlightStore()
        let locator = Self.pdfLocator(page: 5)
        let anchor = AnnotationAnchor.pdf(
            page: 5,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]
        )

        let r1 = try await store.addHighlight(
            locator: locator, anchor: anchor,
            selectedText: "Passage", color: "yellow", note: nil,
            toBookWithKey: Self.bookKey
        )
        let r2 = try await store.addHighlight(
            locator: locator, anchor: anchor,
            selectedText: "Passage", color: "yellow", note: nil,
            toBookWithKey: Self.bookKey
        )

        // Same anchor → must dedupe
        #expect(r1.highlightId == r2.highlightId)

        let all = await store.allHighlights()
        #expect(all.count == 1)
    }

    // MARK: - Nil anchor falls back to profileKey-only dedupe

    @Test func nilAnchorDedupesByProfileKeyOnly() async throws {
        let store = MockHighlightStore()
        let locator = Self.pdfLocator(page: 5)

        let r1 = try await store.addHighlight(
            locator: locator, anchor: nil,
            selectedText: "Passage", color: "yellow", note: nil,
            toBookWithKey: Self.bookKey
        )
        let r2 = try await store.addHighlight(
            locator: locator, anchor: nil,
            selectedText: "Passage again", color: "green", note: nil,
            toBookWithKey: Self.bookKey
        )

        // Both nil anchors, same locator → dedupe
        #expect(r1.highlightId == r2.highlightId)

        let all = await store.allHighlights()
        #expect(all.count == 1)
    }

    // MARK: - One nil anchor, one non-nil → NOT deduped

    @Test func nilAnchorVsNonNilAnchorNotDeduped() async throws {
        let store = MockHighlightStore()
        let locator = Self.pdfLocator(page: 5)
        let anchor = AnnotationAnchor.pdf(
            page: 5,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]
        )

        let r1 = try await store.addHighlight(
            locator: locator, anchor: nil,
            selectedText: "Legacy highlight", color: "yellow", note: nil,
            toBookWithKey: Self.bookKey
        )
        let r2 = try await store.addHighlight(
            locator: locator, anchor: anchor,
            selectedText: "New highlight", color: "yellow", note: nil,
            toBookWithKey: Self.bookKey
        )

        // nil vs non-nil anchor → NOT deduped
        #expect(r1.highlightId != r2.highlightId)

        let all = await store.allHighlights()
        #expect(all.count == 2)
    }

    // MARK: - Text anchors with different offsets → NOT deduped

    @Test func textAnchorsWithDifferentOffsetsNotDeduped() async throws {
        let txtFp = DocumentFingerprint(
            contentSHA256: "2222222222222222222222222222222222222222222222222222222222222222",
            fileByteCount: 512,
            format: .txt
        )
        let locator = Locator(
            bookFingerprint: txtFp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: 0, charRangeEndUTF16: 100,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let store = MockHighlightStore()

        let anchor1 = AnnotationAnchor.text(sourceUnitId: "main", startUTF16: 0, endUTF16: 50)
        let anchor2 = AnnotationAnchor.text(sourceUnitId: "main", startUTF16: 51, endUTF16: 100)

        let r1 = try await store.addHighlight(
            locator: locator, anchor: anchor1,
            selectedText: "First half", color: "yellow", note: nil,
            toBookWithKey: txtFp.canonicalKey
        )
        let r2 = try await store.addHighlight(
            locator: locator, anchor: anchor2,
            selectedText: "Second half", color: "yellow", note: nil,
            toBookWithKey: txtFp.canonicalKey
        )

        #expect(r1.highlightId != r2.highlightId)

        let all = await store.allHighlights()
        #expect(all.count == 2)
    }
}
