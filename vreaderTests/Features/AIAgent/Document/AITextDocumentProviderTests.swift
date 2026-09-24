// Purpose: Feature #177 WI-3 RED contracts for TXT/Markdown document mapping.

import Foundation
import Testing

@Suite("Feature #177 WI-3 — TXT and Markdown mapping")
@MainActor
struct AITextDocumentProviderTests {
    private let txtFingerprint = DocumentFingerprint(
        contentSHA256: String(repeating: "1", count: 64),
        fileByteCount: 100,
        format: .txt
    )
    private let mdFingerprint = DocumentFingerprint(
        contentSHA256: String(repeating: "2", count: 64),
        fileByteCount: 100,
        format: .md
    )

    @Test("TXT chunks preserve exact UTF-16 offsets across emoji, combining marks, and CRLF")
    func txtUTF16Mapping() async throws {
        let text = "A😀e\u{301}\r\n\r\nאבג\r\nsecond"
        let secondStart = (text as NSString).range(of: "אבג").location
        let provider = AITXTDocumentProvider(
            fingerprint: txtFingerprint,
            text: text,
            currentLocator: txtLocator(offset: secondStart)
        )

        let chunks = try await provider.chunks()

        #expect(chunks.map(\.sourceUnitID) == ["txt:segment:0", "txt:segment:1"])
        #expect(chunks[0].globalStartUTF16 == 0)
        #expect(chunks[0].globalEndUTF16 == ("A😀e\u{301}" as NSString).length)
        #expect(chunks[1].globalStartUTF16 == secondStart)
        #expect(chunks[1].text == "אבג\r\nsecond")
        #expect(chunks.allSatisfy { $0.bookFingerprintKey == txtFingerprint.canonicalKey })
    }

    @Test("TXT current UTF-16 offset resolves to its real source unit")
    func txtCurrentOffsetResolvesSegment() async throws {
        let text = "first 😀\n\nsecond paragraph\n\nthird"
        let offset = (text as NSString).range(of: "paragraph").location + 3
        let provider = AITXTDocumentProvider(
            fingerprint: txtFingerprint,
            text: text,
            currentLocator: txtLocator(offset: offset)
        )

        let snapshot = try await provider.snapshot()

        #expect(snapshot.currentSourceUnitID == "txt:segment:1")
        #expect(snapshot.readSoFarBoundary.globalOffsetUTF16 == offset)
        #expect(snapshot.readSoFarBoundary.localOffsetUTF16 == offset - (text as NSString).range(of: "second").location)
        #expect(snapshot.currentLocator?.charOffsetUTF16 == offset)
        #expect(snapshot.exactMappingAvailable)
    }

    @Test("Markdown navigation uses rendered-reader coordinates, not stripped-source guesses")
    func markdownUsesRenderedCoordinateSpace() async throws {
        let markdown = "# כותרת 😀\n\n[קישור](https://example.com) עם **הדגשה** ו־`קוד`\n\n```swift\nlet x = 1\n```"
        let rendered = MDAttributedStringRenderer.render(
            text: markdown,
            config: .default
        ).renderedText
        let codeOffset = (rendered as NSString).range(of: "קוד").location
        let sourceOffset = (markdown as NSString).range(of: "קוד").location
        #expect(codeOffset != sourceOffset)

        let locator = Locator.validated(
            bookFingerprint: mdFingerprint,
            charOffsetUTF16: codeOffset
        )!
        let provider = AIMarkdownDocumentProvider(
            fingerprint: mdFingerprint,
            renderedText: rendered,
            currentLocator: locator
        )

        let snapshot = try await provider.snapshot()
        let allText = try await provider.chunks().map(\.text).joined(separator: "\n\n")

        #expect(snapshot.readSoFarBoundary.globalOffsetUTF16 == codeOffset)
        #expect(snapshot.currentLocator?.charOffsetUTF16 == codeOffset)
        #expect(allText.contains("כותרת 😀"))
        #expect(allText.contains("קישור עם הדגשה ו־קוד"))
        #expect(allText.contains("let x = 1"))
        #expect(!allText.contains("https://example.com"))
        #expect(try await provider.chunks().allSatisfy {
            $0.bookFingerprintKey == mdFingerprint.canonicalKey
        })
    }

    @Test("empty TXT is safe and keeps an exact zero boundary")
    func emptyTXT() async throws {
        let provider = AITXTDocumentProvider(
            fingerprint: txtFingerprint,
            text: "",
            currentLocator: txtLocator(offset: 0)
        )

        let snapshot = try await provider.snapshot()

        #expect(try await provider.chunks().isEmpty)
        #expect(snapshot.currentSourceUnitID == nil)
        #expect(snapshot.readSoFarBoundary.globalOffsetUTF16 == 0)
        #expect(snapshot.exactMappingAvailable)
    }

    private func txtLocator(offset: Int) -> Locator {
        Locator.validated(
            bookFingerprint: txtFingerprint,
            charOffsetUTF16: offset
        )!
    }
}
