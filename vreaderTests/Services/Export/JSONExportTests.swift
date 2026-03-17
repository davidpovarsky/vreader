// Purpose: Tests for JSONExportFormatter — validity, round-trip, ISO 8601 dates.
//
// @coordinates-with: JSONExportFormatter.swift, ExportTestFixtures.swift

import Testing
import Foundation
@testable import vreader

private typealias F = ExportTestFixtures

@Suite("JSONExportFormatter")
struct JSONExportTests {

    // MARK: - Valid JSON

    @Test func validJSON() throws {
        let h = F.makeHighlight(text: "Highlight for JSON")
        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [],
            bookTitle: "JSON Book", bookAuthor: "Author"
        )
        let data = try JSONExportFormatter().format(payload)
        let obj = try JSONSerialization.jsonObject(with: data)
        #expect(obj is [String: Any])
    }

    // MARK: - Round-Trip

    @Test func roundTrippable() throws {
        let h = F.makeHighlight(text: "Round trip text", note: "A note")
        let b = F.makeBookmark(title: "BM")
        let n = F.makeAnnotation(content: "Annotation content")

        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [b], notes: [n],
            bookTitle: "Round Trip", bookAuthor: "Test Author"
        )
        let data = try JSONExportFormatter().format(payload)

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(AnnotationExportPayload.self, from: data)

        #expect(decoded.bookTitle == payload.bookTitle)
        #expect(decoded.bookAuthor == payload.bookAuthor)
        #expect(decoded.annotations.count == payload.annotations.count)

        for (original, restored) in zip(payload.annotations, decoded.annotations) {
            #expect(original.id == restored.id)
            #expect(original.type == restored.type)
            #expect(original.selectedText == restored.selectedText)
            #expect(original.note == restored.note)
            #expect(original.color == restored.color)
            #expect(original.chapter == restored.chapter)
            #expect(original.title == restored.title)
        }
    }

    // MARK: - All Fields Present

    @Test func includesAllFields() throws {
        let h = F.makeHighlight(
            href: "chapter1.xhtml", text: "All fields",
            color: "#ff0000", note: "A note"
        )
        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [],
            bookTitle: "Fields Book", bookAuthor: "Author",
            chapterMap: F.chapterMap
        )
        let json = try formatJSON(payload)

        let requiredKeys = [
            "bookTitle", "bookAuthor", "exportedAt", "annotations",
            "id", "type", "chapter", "selectedText", "note", "color",
            "createdAt", "updatedAt",
        ]
        for key in requiredKeys {
            #expect(json.contains("\"\(key)\""), "Missing key: \(key)")
        }
    }

    // MARK: - ISO 8601 Dates

    @Test func dateFormat_ISO8601() throws {
        let h = F.makeHighlight()
        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [],
            bookTitle: "Date Test", bookAuthor: nil
        )
        let json = try formatJSON(payload)
        // fixedDate (1700000000) = 2023-11-14T22:13:20Z
        #expect(json.contains("2023-11-14T22:13:20Z"))
    }

    // MARK: - Helpers

    private func formatJSON(_ payload: AnnotationExportPayload) throws -> String {
        let data = try JSONExportFormatter().format(payload)
        return String(data: data, encoding: .utf8)!
    }
}
