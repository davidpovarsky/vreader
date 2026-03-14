// Purpose: Tests for HighlightRecord — optional anchor field, backward compatibility.

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("HighlightRecordAnchor")
struct HighlightRecordAnchorTests {

    static let fp = DocumentFingerprint(
        contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        fileByteCount: 1024,
        format: .epub
    )

    @Test func recordWithoutAnchor() {
        let locator = Locator(
            bookFingerprint: Self.fp,
            href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
            cfi: "/6/4", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            anchor: nil,
            profileKey: "key",
            selectedText: "hello",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        #expect(record.anchor == nil)
        #expect(record.locator != nil)
    }

    @Test func recordWithAnchor() {
        let locator = Locator(
            bookFingerprint: Self.fp,
            href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
            cfi: "/6/4", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]",
            endOffset: 5
        )
        let anchor = AnnotationAnchor.epub(
            href: "ch1.xhtml",
            cfi: "/6/4",
            serializedRange: range
        )
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            anchor: anchor,
            profileKey: "key",
            selectedText: "hello",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        #expect(record.anchor == anchor)
    }

    @Test func recordsWithSameFieldsAreEqual() {
        let id = UUID()
        let now = Date()
        let locator = Locator(
            bookFingerprint: Self.fp,
            href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let a = HighlightRecord(
            highlightId: id, locator: locator, anchor: nil,
            profileKey: "k", selectedText: "t", color: "y",
            note: nil, createdAt: now, updatedAt: now
        )
        let b = HighlightRecord(
            highlightId: id, locator: locator, anchor: nil,
            profileKey: "k", selectedText: "t", color: "y",
            note: nil, createdAt: now, updatedAt: now
        )
        #expect(a == b)
    }
}
