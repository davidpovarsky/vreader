// Purpose: Tests for AnnotationExporter — payload building, dispatch, and shared
// edge cases (empty, Unicode, CJK, long text).
//
// @coordinates-with: AnnotationExporter.swift, ExportedAnnotation.swift,
//   ExportTestFixtures.swift

import Testing
import Foundation
@testable import vreader

private typealias F = ExportTestFixtures

@Suite("AnnotationExporter")
struct AnnotationExporterTests {

    // MARK: - buildPayload

    @Test func buildPayload_mixedTypes_allPresent() {
        let h = F.makeHighlight(text: "hl")
        let b = F.makeBookmark(title: "bm")
        let n = F.makeAnnotation(content: "note")

        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [b], notes: [n],
            bookTitle: "Mixed", bookAuthor: nil
        )

        #expect(payload.annotations.count == 3)
        let types = Set(payload.annotations.map(\.type))
        #expect(types.contains(.highlight))
        #expect(types.contains(.bookmark))
        #expect(types.contains(.note))
    }

    @Test func buildPayload_chapterMapping() {
        let h = F.makeHighlight(href: "chapter1.xhtml", text: "mapped")
        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [],
            bookTitle: "T", bookAuthor: nil,
            chapterMap: F.chapterMap
        )
        #expect(payload.annotations[0].chapter == "Chapter 1: Introduction")
    }

    @Test func buildPayload_noChapter_nilChapter() {
        let h = F.makeHighlight(href: nil, text: "no chapter")
        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [],
            bookTitle: "T", bookAuthor: nil
        )
        #expect(payload.annotations[0].chapter == nil)
    }

    // MARK: - Dispatch

    @Test func export_dispatchToCorrectFormatter() throws {
        let payload = AnnotationExporter.buildPayload(
            highlights: [F.makeHighlight()], bookmarks: [], notes: [],
            bookTitle: "Dispatch Test", bookAuthor: nil
        )

        let mdData = try AnnotationExporter.export(payload: payload, format: .markdown)
        let md = String(data: mdData, encoding: .utf8)!
        #expect(md.contains("# Dispatch Test"))

        let jsonData = try AnnotationExporter.export(payload: payload, format: .json)
        let json = String(data: jsonData, encoding: .utf8)!
        #expect(json.contains("\"bookTitle\""))
    }

    // MARK: - ExportFormat Codable

    @Test func exportFormat_enum_codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for format in ExportFormat.allCases {
            let data = try encoder.encode(format)
            let decoded = try decoder.decode(ExportFormat.self, from: data)
            #expect(decoded == format)
        }
    }

    // MARK: - Empty Annotations

    @Test func emptyAnnotations_producesMinimalOutput() throws {
        let payload = AnnotationExporter.buildPayload(
            highlights: [], bookmarks: [], notes: [],
            bookTitle: "Empty Book", bookAuthor: nil
        )

        // Markdown: minimal
        let mdData = try MarkdownExportFormatter().format(payload)
        let md = String(data: mdData, encoding: .utf8)!
        #expect(md.contains("# Empty Book"))
        #expect(md.contains("*No annotations.*"))

        // JSON: empty array
        let jsonData = try JSONExportFormatter().format(payload)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(AnnotationExportPayload.self, from: jsonData)
        #expect(decoded.annotations.isEmpty)
    }

    // MARK: - Unicode

    @Test func unicodeContent_preserved() throws {
        let h = F.makeHighlight(text: "Caf\u{0301}e resum\u{0301}e na\u{00EF}ve")
        let n = F.makeAnnotation(content: "Notes with emoji: \u{1F4DA}\u{2728}")

        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [n],
            bookTitle: "Unicode \u{1F30D} Book", bookAuthor: nil
        )

        // Markdown preserves
        let mdData = try MarkdownExportFormatter().format(payload)
        let md = String(data: mdData, encoding: .utf8)!
        #expect(md.contains("Caf\u{0301}e"))
        #expect(md.contains("\u{1F4DA}"))

        // JSON round-trip preserves
        let jsonData = try JSONExportFormatter().format(payload)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(AnnotationExportPayload.self, from: jsonData)
        let hl = decoded.annotations.first { $0.type == .highlight }
        #expect(hl?.selectedText == "Caf\u{0301}e resum\u{0301}e na\u{00EF}ve")
    }

    // MARK: - CJK

    @Test func cjkText_correct() throws {
        let h = F.makeHighlight(text: "\u{4E16}\u{754C}\u{4F60}\u{597D}")
        let n = F.makeAnnotation(content: "\u{65E5}\u{672C}\u{8A9E}\u{306E}\u{30CE}\u{30FC}\u{30C8}")

        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [n],
            bookTitle: "\u{4E2D}\u{6587}\u{4E66}\u{7C4D}",
            bookAuthor: "\u{4F5C}\u{8005}\u{540D}"
        )

        let mdData = try MarkdownExportFormatter().format(payload)
        let md = String(data: mdData, encoding: .utf8)!
        #expect(md.contains("\u{4E16}\u{754C}\u{4F60}\u{597D}"))
        #expect(md.contains("# \u{4E2D}\u{6587}\u{4E66}\u{7C4D}"))

        let jsonData = try JSONExportFormatter().format(payload)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(AnnotationExportPayload.self, from: jsonData)
        #expect(decoded.bookTitle == "\u{4E2D}\u{6587}\u{4E66}\u{7C4D}")
        #expect(decoded.bookAuthor == "\u{4F5C}\u{8005}\u{540D}")
    }

    // MARK: - Long Text

    @Test func longNote_notTruncated() throws {
        let longText = String(repeating: "This is a very long sentence. ", count: 100)
        let h = F.makeHighlight(text: longText, note: longText)

        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [],
            bookTitle: "Long Note Book", bookAuthor: nil
        )

        let mdData = try MarkdownExportFormatter().format(payload)
        let md = String(data: mdData, encoding: .utf8)!
        #expect(md.contains(longText))

        let jsonData = try JSONExportFormatter().format(payload)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(AnnotationExportPayload.self, from: jsonData)
        #expect(decoded.annotations[0].selectedText == longText)
        #expect(decoded.annotations[0].note == longText)
    }
}
