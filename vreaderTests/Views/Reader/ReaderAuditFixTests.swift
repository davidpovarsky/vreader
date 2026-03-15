// Purpose: Tests for high-severity audit fixes.
// Issue 1: AI panel locator should use live reader position.
// Issue 2: EPUB AI context should extract text from spine items, not raw ZIP.
// Issue 3/4: Selection menus should support "Add Note" with persistence.

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
@testable import vreader

// MARK: - Issue 1: readerPositionDidChange notification

@Suite("ReaderAuditFix — Issue 1: live locator notification")
struct ReaderLiveLocatorTests {

    @Test("readerPositionDidChange notification posts a Locator object")
    func positionNotificationPostsLocator() async {
        let fingerprint = DocumentFingerprint(
            contentSHA256: "audit_test_sha256_000000000000000000000000000000000000000000000",
            fileByteCount: 5000,
            format: .epub
        )
        let locator = Locator(
            bookFingerprint: fingerprint,
            href: "chapter3.xhtml",
            progression: 0.75,
            totalProgression: 0.5,
            cfi: nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: nil,
            textContextBefore: nil,
            textContextAfter: nil
        )

        var received: Locator?
        let expectation = NotificationCenter.default.addObserver(
            forName: .readerPositionDidChange,
            object: nil,
            queue: .main
        ) { notification in
            received = notification.object as? Locator
        }

        NotificationCenter.default.post(
            name: .readerPositionDidChange,
            object: locator
        )

        // Give notification time to be delivered on main queue
        try? await Task.sleep(for: .milliseconds(50))

        #expect(received != nil, "Should receive a Locator from the notification")
        #expect(received?.href == "chapter3.xhtml")
        #expect(received?.progression == 0.75)

        NotificationCenter.default.removeObserver(expectation)
    }

    @Test("PDF locator is posted with page info")
    func pdfPositionNotification() async {
        let fingerprint = DocumentFingerprint(
            contentSHA256: "audit_test_pdf_sha256_00000000000000000000000000000000000000000000",
            fileByteCount: 8000,
            format: .pdf
        )
        let locator = LocatorFactory.pdf(fingerprint: fingerprint, page: 42, totalProgression: 0.8)

        var received: Locator?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerPositionDidChange,
            object: nil,
            queue: .main
        ) { notification in
            received = notification.object as? Locator
        }

        NotificationCenter.default.post(
            name: .readerPositionDidChange,
            object: locator
        )

        try? await Task.sleep(for: .milliseconds(50))

        #expect(received?.page == 42)

        NotificationCenter.default.removeObserver(observer)
    }
}

// MARK: - Issue 2: EPUB text extraction for AI context

@Suite("ReaderAuditFix — Issue 2: EPUB AI text extraction")
struct EPUBAITextExtractionTests {

    @Test("stripHTML extracts readable text from EPUB XHTML")
    func stripHTMLExtractsText() {
        let xhtml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Chapter 1</title></head>
        <body>
        <h1>Introduction</h1>
        <p>This is the first paragraph of the book.</p>
        <p>Second paragraph with <em>emphasis</em> and <strong>bold</strong>.</p>
        </body>
        </html>
        """
        let text = EPUBTextExtractor.stripHTML(xhtml)
        #expect(text.contains("Introduction"))
        #expect(text.contains("first paragraph"))
        #expect(text.contains("emphasis"))
        #expect(text.contains("bold"))
        // Should NOT contain raw tags
        #expect(!text.contains("<h1>"))
        #expect(!text.contains("<p>"))
    }

    @Test("stripHTML handles EPUB with script and style blocks")
    func stripHTMLRemovesScriptStyle() {
        let xhtml = """
        <html><head>
        <style>body { font-size: 16px; }</style>
        </head><body>
        <p>Real content here.</p>
        <script>var x = 1;</script>
        </body></html>
        """
        let text = EPUBTextExtractor.stripHTML(xhtml)
        #expect(text.contains("Real content here"))
        #expect(!text.contains("font-size"))
        #expect(!text.contains("var x"))
    }

    @Test("stripHTML handles empty XHTML")
    func stripHTMLEmpty() {
        let text = EPUBTextExtractor.stripHTML("")
        #expect(text.isEmpty)
    }

    @Test("stripHTML handles CJK content")
    func stripHTMLCJK() {
        let xhtml = "<p>这是第一章。<ruby>汉字<rt>hànzì</rt></ruby>的故事。</p>"
        let text = EPUBTextExtractor.stripHTML(xhtml)
        #expect(text.contains("这是第一章"))
        #expect(text.contains("的故事"))
    }

    @Test("extractFromParser concatenates all spine item text")
    func extractAllSpineText() async throws {
        let parser = MockEPUBParserForAIContext(spineContent: [
            "ch1.xhtml": "<p>Chapter one content about philosophy.</p>",
            "ch2.xhtml": "<p>Chapter two discusses mathematics.</p>",
            "ch3.xhtml": "<p>Chapter three covers history.</p>",
        ], spineOrder: ["ch1.xhtml", "ch2.xhtml", "ch3.xhtml"])

        let metadata = try await parser.open(url: URL(fileURLWithPath: "/tmp/test.epub"))
        let extractor = EPUBTextExtractor()
        let units = try await extractor.extractFromParser(parser, metadata: metadata)

        #expect(units.count == 3)
        #expect(units[0].text.contains("philosophy"))
        #expect(units[1].text.contains("mathematics"))
        #expect(units[2].text.contains("history"))
    }

    @Test("extractFromParser skips empty chapters")
    func extractSkipsEmpty() async throws {
        let parser = MockEPUBParserForAIContext(spineContent: [
            "ch1.xhtml": "<p>Has content</p>",
            "ch2.xhtml": "<html><body>   </body></html>",
        ], spineOrder: ["ch1.xhtml", "ch2.xhtml"])

        let metadata = try await parser.open(url: URL(fileURLWithPath: "/tmp/test.epub"))
        let extractor = EPUBTextExtractor()
        let units = try await extractor.extractFromParser(parser, metadata: metadata)

        #expect(units.count == 1)
        #expect(units[0].text.contains("Has content"))
    }

    @Test("extractFromParser handles parser error gracefully")
    func extractHandlesError() async throws {
        let parser = MockEPUBParserForAIContext(
            spineContent: [:],
            spineOrder: ["missing.xhtml"],
            shouldThrow: true
        )

        let metadata = try await parser.open(url: URL(fileURLWithPath: "/tmp/test.epub"))
        let extractor = EPUBTextExtractor()
        let units = try await extractor.extractFromParser(parser, metadata: metadata)

        #expect(units.isEmpty)
    }
}

// MARK: - Issue 3/4: Add Note in selection menus

@Suite("ReaderAuditFix — Issue 3/4: highlight with note persistence")
struct HighlightWithNoteTests {

    // MARK: - Helpers

    private static let testFingerprint = DocumentFingerprint(
        contentSHA256: "audit_note_sha256_0000000000000000000000000000000000000000000000",
        fileByteCount: 3000,
        format: .epub
    )

    private func makeLocator() -> Locator {
        Locator(
            bookFingerprint: Self.testFingerprint,
            href: "ch1.xhtml",
            progression: 0.5,
            totalProgression: nil,
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

    private func makeEvent(text: String = "Selected text") -> ReaderSelectionEvent {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: text.count
        )
        let anchor = AnnotationAnchor.epub(href: "ch1.xhtml", cfi: "", serializedRange: range)
        return ReaderSelectionEvent(
            selectedText: text,
            anchor: anchor,
            sourceRect: CGRect(x: 0, y: 0, width: 100, height: 20)
        )
    }

    // MARK: - Tests

    @Test("addHighlight with note persists the note text")
    func addHighlightWithNote() async throws {
        let store = MockHighlightStore()
        let locator = makeLocator()
        let event = makeEvent()

        let record = try await store.addHighlight(
            locator: locator,
            anchor: event.anchor,
            selectedText: event.selectedText,
            color: "yellow",
            note: "This is my note about the passage",
            toBookWithKey: Self.testFingerprint.canonicalKey
        )

        #expect(record.note == "This is my note about the passage")
        #expect(record.selectedText == "Selected text")
        #expect(record.color == "yellow")
    }

    @Test("addHighlight with empty note stores nil-equivalent")
    func addHighlightWithEmptyNote() async throws {
        let store = MockHighlightStore()
        let locator = makeLocator()
        let event = makeEvent()

        let record = try await store.addHighlight(
            locator: locator,
            anchor: event.anchor,
            selectedText: event.selectedText,
            color: "yellow",
            note: "",
            toBookWithKey: Self.testFingerprint.canonicalKey
        )

        // Empty note is stored as-is (caller should convert empty to nil if desired)
        #expect(record.note == "")
    }

    @Test("addHighlight with nil note stores no note")
    func addHighlightWithNilNote() async throws {
        let store = MockHighlightStore()
        let locator = makeLocator()
        let event = makeEvent()

        let record = try await store.addHighlight(
            locator: locator,
            anchor: event.anchor,
            selectedText: event.selectedText,
            color: "yellow",
            note: nil,
            toBookWithKey: Self.testFingerprint.canonicalKey
        )

        #expect(record.note == nil)
    }

    @Test("updateHighlightNote updates an existing highlight")
    func updateNote() async throws {
        let store = MockHighlightStore()
        let locator = makeLocator()
        let event = makeEvent()

        let record = try await store.addHighlight(
            locator: locator,
            anchor: event.anchor,
            selectedText: event.selectedText,
            color: "yellow",
            note: nil,
            toBookWithKey: Self.testFingerprint.canonicalKey
        )

        try await store.updateHighlightNote(highlightId: record.highlightId, note: "Added later")

        let highlights = try await store.fetchHighlights(
            forBookWithKey: Self.testFingerprint.canonicalKey
        )
        let updated = highlights.first { $0.highlightId == record.highlightId }
        #expect(updated?.note == "Added later")
    }

    @Test("addHighlight with long note text")
    func addHighlightWithLongNote() async throws {
        let store = MockHighlightStore()
        let locator = makeLocator()
        let event = makeEvent()
        let longNote = String(repeating: "This is a very detailed note. ", count: 100)

        let record = try await store.addHighlight(
            locator: locator,
            anchor: event.anchor,
            selectedText: event.selectedText,
            color: "yellow",
            note: longNote,
            toBookWithKey: Self.testFingerprint.canonicalKey
        )

        #expect(record.note == longNote)
    }

    @Test("addHighlight with Unicode/CJK note text")
    func addHighlightWithCJKNote() async throws {
        let store = MockHighlightStore()
        let locator = makeLocator()
        let event = makeEvent(text: "这段话很有意思")
        let cjkNote = "这是一个关于哲学的笔记。包含emoji: 📚"

        let record = try await store.addHighlight(
            locator: locator,
            anchor: event.anchor,
            selectedText: event.selectedText,
            color: "yellow",
            note: cjkNote,
            toBookWithKey: Self.testFingerprint.canonicalKey
        )

        #expect(record.note == cjkNote)
        #expect(record.selectedText == "这段话很有意思")
    }

    @Test("PDF highlight with note persists correctly")
    func pdfHighlightWithNote() async throws {
        let store = MockHighlightStore()
        let pdfFP = DocumentFingerprint(
            contentSHA256: "audit_pdf_note_sha2560000000000000000000000000000000000000000000",
            fileByteCount: 8000,
            format: .pdf
        )
        let locator = LocatorFactory.pdf(fingerprint: pdfFP, page: 5)!
        let anchor = AnnotationAnchor.pdf(page: 5, rects: [
            .init(x: 10, y: 20, width: 100, height: 15)
        ])

        let record = try await store.addHighlight(
            locator: locator,
            anchor: anchor,
            selectedText: "PDF selected text",
            color: "yellow",
            note: "My PDF note",
            toBookWithKey: pdfFP.canonicalKey
        )

        #expect(record.note == "My PDF note")
        #expect(record.selectedText == "PDF selected text")
    }
}

// MARK: - Mock Parser for AI Context Tests

/// Minimal mock for testing EPUB text extraction for AI context.
private actor MockEPUBParserForAIContext: EPUBParserProtocol {
    let spineContent: [String: String]
    let spineOrder: [String]
    let shouldThrow: Bool
    private var _isOpen = false

    var isOpen: Bool { _isOpen }

    init(spineContent: [String: String], spineOrder: [String], shouldThrow: Bool = false) {
        self.spineContent = spineContent
        self.spineOrder = spineOrder
        self.shouldThrow = shouldThrow
    }

    func open(url: URL) async throws -> EPUBMetadata {
        _isOpen = true
        let items = spineOrder.enumerated().map { index, href in
            EPUBSpineItem(id: "item\(index)", href: href, title: nil, index: index)
        }
        return EPUBMetadata(
            title: "Test Book",
            author: nil,
            language: "en",
            readingDirection: .ltr,
            layout: .reflowable,
            spineItems: items
        )
    }

    func close() async { _isOpen = false }

    func contentForSpineItem(href: String) async throws -> String {
        if shouldThrow { throw EPUBParserError.resourceNotFound(href) }
        return spineContent[href] ?? ""
    }

    func resourceBaseURL() async throws -> URL {
        URL(fileURLWithPath: "/tmp/test-epub")
    }

    func extractedRootURL() async throws -> URL {
        URL(fileURLWithPath: "/tmp/test-epub")
    }
}
#endif
