// Purpose: Tests for AnnotationAnchor — Codable round-trip, equality, edge cases.

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("AnnotationAnchor")
struct AnnotationAnchorTests {

    // MARK: - EPUB Anchor

    @Test func epubAnchorRoundTrips() throws {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/div[1]/p[3]/text()",
            startOffset: 42,
            endContainerPath: "/html/body/div[1]/p[3]/text()",
            endOffset: 87
        )
        let anchor = AnnotationAnchor.epub(
            href: "chapter1.xhtml",
            cfi: "/6/4!/4/2:0",
            serializedRange: range
        )
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AnnotationAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    @Test func epubAnchorWithEmptyStrings() throws {
        let range = EPUBSerializedRange(
            startContainerPath: "",
            startOffset: 0,
            endContainerPath: "",
            endOffset: 0
        )
        let anchor = AnnotationAnchor.epub(href: "", cfi: "", serializedRange: range)
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AnnotationAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    @Test func epubAnchorWithUnicodeInXPath() throws {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/div[@class='中文']/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/div[@class='中文']/p[1]/text()",
            endOffset: 5
        )
        let anchor = AnnotationAnchor.epub(
            href: "第一章.xhtml",
            cfi: "/6/4",
            serializedRange: range
        )
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AnnotationAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    // MARK: - PDF Anchor

    @Test func pdfAnchorRoundTrips() throws {
        let rects = [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.05)]
        let anchor = AnnotationAnchor.pdf(page: 0, rects: rects)
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AnnotationAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    @Test func pdfAnchorWithMultipleRects() throws {
        let rects = [
            CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.02),
            CGRect(x: 0.1, y: 0.78, width: 0.8, height: 0.02),
            CGRect(x: 0.1, y: 0.76, width: 0.3, height: 0.02)
        ]
        let anchor = AnnotationAnchor.pdf(page: 42, rects: rects)
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AnnotationAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    @Test func pdfAnchorWithEmptyRects() throws {
        let anchor = AnnotationAnchor.pdf(page: 0, rects: [])
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AnnotationAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    @Test func pdfAnchorWithZeroAreaRect() throws {
        let rects = [CGRect(x: 0.5, y: 0.5, width: 0.0, height: 0.0)]
        let anchor = AnnotationAnchor.pdf(page: 3, rects: rects)
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AnnotationAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    @Test func pdfAnchorPageZero() throws {
        let anchor = AnnotationAnchor.pdf(page: 0, rects: [CGRect(x: 0, y: 0, width: 1, height: 1)])
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AnnotationAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    // MARK: - Text Anchor

    @Test func txtAnchorRoundTrips() throws {
        let anchor = AnnotationAnchor.text(
            sourceUnitId: "unit-001",
            startUTF16: 100,
            endUTF16: 250
        )
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AnnotationAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    @Test func txtAnchorWithZeroRange() throws {
        let anchor = AnnotationAnchor.text(sourceUnitId: "main", startUTF16: 0, endUTF16: 0)
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AnnotationAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    @Test func txtAnchorWithLargeOffsets() throws {
        let anchor = AnnotationAnchor.text(
            sourceUnitId: "large-doc",
            startUTF16: 2_147_483_000,
            endUTF16: 2_147_483_647
        )
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AnnotationAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    @Test func txtAnchorWithEmptySourceUnitId() throws {
        let anchor = AnnotationAnchor.text(sourceUnitId: "", startUTF16: 0, endUTF16: 10)
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AnnotationAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    // MARK: - Equality

    @Test func sameEpubAnchorsAreEqual() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 10
        )
        let a = AnnotationAnchor.epub(href: "ch1.xhtml", cfi: "/6/4", serializedRange: range)
        let b = AnnotationAnchor.epub(href: "ch1.xhtml", cfi: "/6/4", serializedRange: range)
        #expect(a == b)
    }

    @Test func differentAnchorsAreNotEqual() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 10
        )
        let epub = AnnotationAnchor.epub(href: "ch1.xhtml", cfi: "/6/4", serializedRange: range)
        let pdf = AnnotationAnchor.pdf(page: 0, rects: [])
        let text = AnnotationAnchor.text(sourceUnitId: "u1", startUTF16: 0, endUTF16: 10)
        #expect(epub != pdf)
        #expect(pdf != text)
        #expect(epub != text)
    }

    @Test func epubAnchorsWithDifferentOffsetsAreNotEqual() {
        let range1 = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 10
        )
        let range2 = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 20
        )
        let a = AnnotationAnchor.epub(href: "ch1.xhtml", cfi: "/6/4", serializedRange: range1)
        let b = AnnotationAnchor.epub(href: "ch1.xhtml", cfi: "/6/4", serializedRange: range2)
        #expect(a != b)
    }

    // MARK: - EPUBSerializedRange

    @Test func epubSerializedRangeRoundTrips() throws {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/div[2]/p[1]/text()",
            startOffset: 15,
            endContainerPath: "/html/body/div[2]/p[3]/text()",
            endOffset: 42
        )
        let data = try JSONEncoder().encode(range)
        let decoded = try JSONDecoder().decode(EPUBSerializedRange.self, from: data)
        #expect(decoded == range)
    }

    @Test func epubSerializedRangeEquality() {
        let a = EPUBSerializedRange(
            startContainerPath: "/a", startOffset: 0,
            endContainerPath: "/b", endOffset: 5
        )
        let b = EPUBSerializedRange(
            startContainerPath: "/a", startOffset: 0,
            endContainerPath: "/b", endOffset: 5
        )
        #expect(a == b)
    }

    @Test func epubSerializedRangeInequality() {
        let a = EPUBSerializedRange(
            startContainerPath: "/a", startOffset: 0,
            endContainerPath: "/b", endOffset: 5
        )
        let b = EPUBSerializedRange(
            startContainerPath: "/a", startOffset: 1,
            endContainerPath: "/b", endOffset: 5
        )
        #expect(a != b)
    }

    // MARK: - anchorHash

    @Test func anchorHashIsStableAcrossCalls() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 10
        )
        let anchor = AnnotationAnchor.epub(href: "ch1.xhtml", cfi: "/6/4", serializedRange: range)
        let hash1 = anchor.anchorHash
        let hash2 = anchor.anchorHash
        #expect(hash1 == hash2)
    }

    @Test func anchorHashDiffersForDifferentEpubRanges() {
        let range1 = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 10
        )
        let range2 = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 20
        )
        let a = AnnotationAnchor.epub(href: "ch1.xhtml", cfi: "/6/4", serializedRange: range1)
        let b = AnnotationAnchor.epub(href: "ch1.xhtml", cfi: "/6/4", serializedRange: range2)
        #expect(a.anchorHash != b.anchorHash)
    }

    @Test func anchorHashDiffersForDifferentPdfRects() {
        let a = AnnotationAnchor.pdf(page: 5, rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.05)])
        let b = AnnotationAnchor.pdf(page: 5, rects: [CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.05)])
        #expect(a.anchorHash != b.anchorHash)
    }

    @Test func anchorHashSameForEqualAnchors() {
        let a = AnnotationAnchor.pdf(page: 3, rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.05)])
        let b = AnnotationAnchor.pdf(page: 3, rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.05)])
        #expect(a.anchorHash == b.anchorHash)
    }

    @Test func anchorHashDiffersAcrossAnchorTypes() {
        let epub = AnnotationAnchor.epub(
            href: "ch1.xhtml", cfi: "/6/4",
            serializedRange: EPUBSerializedRange(
                startContainerPath: "/a", startOffset: 0,
                endContainerPath: "/a", endOffset: 5
            )
        )
        let pdf = AnnotationAnchor.pdf(page: 0, rects: [])
        let text = AnnotationAnchor.text(sourceUnitId: "u1", startUTF16: 0, endUTF16: 5)
        #expect(epub.anchorHash != pdf.anchorHash)
        #expect(pdf.anchorHash != text.anchorHash)
        #expect(epub.anchorHash != text.anchorHash)
    }

    @Test func anchorHashIsValidSHA256Hex() {
        let anchor = AnnotationAnchor.text(sourceUnitId: "main", startUTF16: 0, endUTF16: 10)
        let hash = anchor.anchorHash
        // SHA-256 produces 64 hex characters
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit })
    }

    @Test func anchorHashDiffersForDifferentTextOffsets() {
        let a = AnnotationAnchor.text(sourceUnitId: "unit", startUTF16: 0, endUTF16: 100)
        let b = AnnotationAnchor.text(sourceUnitId: "unit", startUTF16: 50, endUTF16: 150)
        #expect(a.anchorHash != b.anchorHash)
    }
}
