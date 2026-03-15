// Purpose: Tests for Highlight anchor storage resilience — verifies that the
// anchorData-backed computed property correctly round-trips all anchor types,
// returns nil for legacy (nil) highlights, and gracefully handles corrupted data.
//
// @coordinates-with: Highlight.swift, AnnotationAnchor.swift, SchemaV2.swift

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("HighlightAnchorStorage")
struct HighlightAnchorStorageTests {

    // MARK: - Helpers

    private static let fp = DocumentFingerprint(
        contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        fileByteCount: 1024,
        format: .pdf
    )

    private static func makeLocator(page: Int = 1) -> Locator {
        Locator(
            bookFingerprint: fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: page,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    private static let epubFp = DocumentFingerprint(
        contentSHA256: "1111111111111111111111111111111111111111111111111111111111111111",
        fileByteCount: 4096,
        format: .epub
    )

    private static func makeEpubLocator() -> Locator {
        Locator(
            bookFingerprint: epubFp,
            href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
            cfi: "/6/4", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    private static let txtFp = DocumentFingerprint(
        contentSHA256: "2222222222222222222222222222222222222222222222222222222222222222",
        fileByteCount: 512,
        format: .txt
    )

    private static func makeTxtLocator() -> Locator {
        Locator(
            bookFingerprint: txtFp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: 100, charRangeEndUTF16: 200,
            textQuote: "selected text", textContextBefore: nil, textContextAfter: nil
        )
    }

    // MARK: - PDF Anchor Round-Trip

    @Test func anchorRoundTripPDF() {
        let anchor = AnnotationAnchor.pdf(
            page: 5,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)]
        )
        let highlight = Highlight(
            locator: Self.makeLocator(page: 5),
            selectedText: "PDF text",
            anchor: anchor
        )
        #expect(highlight.anchor == anchor)
    }

    // MARK: - EPUB Anchor Round-Trip

    @Test func anchorRoundTripEPUB() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 10
        )
        let anchor = AnnotationAnchor.epub(
            href: "ch1.xhtml",
            cfi: "/6/4",
            serializedRange: range
        )
        let highlight = Highlight(
            locator: Self.makeEpubLocator(),
            selectedText: "EPUB text",
            anchor: anchor
        )
        #expect(highlight.anchor == anchor)
    }

    // MARK: - Text Anchor Round-Trip

    @Test func anchorRoundTripText() {
        let anchor = AnnotationAnchor.text(
            sourceUnitId: "main",
            startUTF16: 100,
            endUTF16: 200
        )
        let highlight = Highlight(
            locator: Self.makeTxtLocator(),
            selectedText: "plain text",
            anchor: anchor
        )
        #expect(highlight.anchor == anchor)
    }

    // MARK: - Legacy Highlight (nil anchor, no crash)

    @Test func anchorNilForLegacyHighlight() {
        let highlight = Highlight(
            locator: Self.makeLocator(),
            selectedText: "legacy text"
        )
        // Must not crash and must return nil
        #expect(highlight.anchor == nil)
    }

    // MARK: - Corrupted anchorData Returns nil

    @Test func anchorCorruptedDataReturnsNil() {
        let highlight = Highlight(
            locator: Self.makeLocator(),
            selectedText: "corrupted"
        )
        // Simulate corrupted data by setting anchorData to garbage bytes
        highlight.anchorData = Data([0xFF, 0xFE, 0x00, 0x01])
        #expect(highlight.anchor == nil)
    }

    // MARK: - Empty Data Returns nil

    @Test func anchorEmptyDataReturnsNil() {
        let highlight = Highlight(
            locator: Self.makeLocator(),
            selectedText: "empty"
        )
        highlight.anchorData = Data()
        #expect(highlight.anchor == nil)
    }

    // MARK: - updateAnchor then nil

    @Test func updateAnchorThenClear() {
        let highlight = Highlight(
            locator: Self.makeLocator(),
            selectedText: "toggle"
        )
        let anchor = AnnotationAnchor.pdf(page: 3, rects: [])
        highlight.updateAnchor(anchor)
        #expect(highlight.anchor == anchor)

        highlight.updateAnchor(nil)
        #expect(highlight.anchor == nil)
        #expect(highlight.anchorData == nil)
    }

    // MARK: - updateAnchor toggles correctly

    @Test func updateAnchorToggle() {
        let highlight = Highlight(
            locator: Self.makeLocator(),
            selectedText: "toggle"
        )
        let anchor1 = AnnotationAnchor.pdf(page: 1, rects: [CGRect(x: 0, y: 0, width: 1, height: 1)])
        let anchor2 = AnnotationAnchor.pdf(page: 2, rects: [CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)])

        highlight.updateAnchor(anchor1)
        #expect(highlight.anchor == anchor1)

        highlight.updateAnchor(nil)
        #expect(highlight.anchor == nil)

        highlight.updateAnchor(anchor2)
        #expect(highlight.anchor == anchor2)
    }

    // MARK: - Init with anchor encodes to anchorData

    @Test func initWithAnchorPopulatesAnchorData() {
        let anchor = AnnotationAnchor.text(sourceUnitId: "u1", startUTF16: 0, endUTF16: 50)
        let highlight = Highlight(
            locator: Self.makeTxtLocator(),
            selectedText: "init test",
            anchor: anchor
        )
        #expect(highlight.anchorData != nil)
        #expect(highlight.anchor == anchor)
    }

    // MARK: - Init without anchor keeps anchorData nil

    @Test func initWithoutAnchorKeepsAnchorDataNil() {
        let highlight = Highlight(
            locator: Self.makeLocator(),
            selectedText: "no anchor"
        )
        #expect(highlight.anchorData == nil)
        #expect(highlight.anchor == nil)
    }
}
