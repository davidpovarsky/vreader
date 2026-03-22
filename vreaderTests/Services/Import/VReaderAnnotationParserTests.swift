// Purpose: Tests for VReaderAnnotationParser — parses ExportedAnnotation arrays
// from JSON data produced by C02's JSONExportFormatter.
//
// @coordinates-with: VReaderAnnotationParser.swift, ExportedAnnotation.swift

import Testing
import Foundation
@testable import vreader

@Suite("VReaderAnnotationParser")
struct VReaderAnnotationParserTests {

    // MARK: - Helpers

    /// Encodes a payload to JSON data using the same strategy as JSONExportFormatter.
    private func encode(_ payload: AnnotationExportPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z

    private func makePayload(
        annotations: [ExportedAnnotation] = [],
        bookTitle: String = "Test Book",
        bookAuthor: String? = "Author"
    ) -> AnnotationExportPayload {
        AnnotationExportPayload(
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            exportedAt: fixedDate,
            annotations: annotations
        )
    }

    private func makeExportedHighlight(
        id: UUID = UUID(),
        chapter: String? = "Chapter 1",
        text: String = "Highlighted text",
        note: String? = nil,
        color: String? = "yellow"
    ) -> ExportedAnnotation {
        ExportedAnnotation(
            id: id, type: .highlight, chapter: chapter,
            selectedText: text, note: note, color: color, title: nil,
            createdAt: fixedDate, updatedAt: fixedDate
        )
    }

    private func makeExportedBookmark(
        id: UUID = UUID(),
        chapter: String? = "Chapter 2",
        title: String? = "My Bookmark"
    ) -> ExportedAnnotation {
        ExportedAnnotation(
            id: id, type: .bookmark, chapter: chapter,
            selectedText: nil, note: nil, color: nil, title: title,
            createdAt: fixedDate, updatedAt: fixedDate
        )
    }

    private func makeExportedNote(
        id: UUID = UUID(),
        chapter: String? = "Chapter 3",
        content: String = "A user note"
    ) -> ExportedAnnotation {
        ExportedAnnotation(
            id: id, type: .note, chapter: chapter,
            selectedText: nil, note: content, color: nil, title: nil,
            createdAt: fixedDate, updatedAt: fixedDate
        )
    }

    // MARK: - Happy Path

    @Test func parseValidPayload_returnsAnnotations() throws {
        let h = makeExportedHighlight(text: "Hello")
        let b = makeExportedBookmark(title: "BM")
        let n = makeExportedNote(content: "Note")
        let data = try encode(makePayload(annotations: [h, b, n]))

        let result = try VReaderAnnotationParser.parse(data: data)

        #expect(result.bookTitle == "Test Book")
        #expect(result.bookAuthor == "Author")
        #expect(result.annotations.count == 3)
    }

    @Test func parseHighlight_fieldsPreserved() throws {
        let id = UUID()
        let h = makeExportedHighlight(id: id, chapter: "Ch1", text: "Selected", note: "My note", color: "#ff0000")
        let data = try encode(makePayload(annotations: [h]))

        let result = try VReaderAnnotationParser.parse(data: data)
        let annotation = try #require(result.annotations.first)

        #expect(annotation.id == id)
        #expect(annotation.type == .highlight)
        #expect(annotation.chapter == "Ch1")
        #expect(annotation.selectedText == "Selected")
        #expect(annotation.note == "My note")
        #expect(annotation.color == "#ff0000")
    }

    @Test func parseBookmark_fieldsPreserved() throws {
        let id = UUID()
        let b = makeExportedBookmark(id: id, chapter: "Ch2", title: "Bookmark Title")
        let data = try encode(makePayload(annotations: [b]))

        let result = try VReaderAnnotationParser.parse(data: data)
        let annotation = try #require(result.annotations.first)

        #expect(annotation.id == id)
        #expect(annotation.type == .bookmark)
        #expect(annotation.title == "Bookmark Title")
    }

    @Test func parseNote_fieldsPreserved() throws {
        let id = UUID()
        let n = makeExportedNote(id: id, content: "My note content")
        let data = try encode(makePayload(annotations: [n]))

        let result = try VReaderAnnotationParser.parse(data: data)
        let annotation = try #require(result.annotations.first)

        #expect(annotation.id == id)
        #expect(annotation.type == .note)
        #expect(annotation.note == "My note content")
    }

    // MARK: - Date Parsing

    @Test func datesParsed_ISO8601() throws {
        let h = makeExportedHighlight()
        let data = try encode(makePayload(annotations: [h]))

        let result = try VReaderAnnotationParser.parse(data: data)
        let annotation = try #require(result.annotations.first)

        // fixedDate = 1_700_000_000
        #expect(annotation.createdAt.timeIntervalSince1970 == 1_700_000_000)
        #expect(annotation.updatedAt.timeIntervalSince1970 == 1_700_000_000)
    }

    // MARK: - Empty Array

    @Test func emptyAnnotationsArray_parsesSuccessfully() throws {
        let data = try encode(makePayload(annotations: []))

        let result = try VReaderAnnotationParser.parse(data: data)

        #expect(result.annotations.isEmpty)
        #expect(result.bookTitle == "Test Book")
    }

    // MARK: - Malformed JSON

    @Test func malformedJSON_throwsError() {
        let garbage = Data("not json at all".utf8)

        #expect(throws: AnnotationImportError.self) {
            try VReaderAnnotationParser.parse(data: garbage)
        }
    }

    @Test func emptyData_throwsError() {
        let empty = Data()

        #expect(throws: AnnotationImportError.self) {
            try VReaderAnnotationParser.parse(data: empty)
        }
    }

    @Test func truncatedJSON_throwsError() {
        let truncated = Data("{\"bookTitle\":\"Test".utf8)

        #expect(throws: AnnotationImportError.self) {
            try VReaderAnnotationParser.parse(data: truncated)
        }
    }

    // MARK: - Future Fields Ignored

    @Test func futureFields_ignored() throws {
        // Hand-craft JSON with extra unknown fields
        let json = """
        {
            "bookTitle": "Future Book",
            "bookAuthor": "Author",
            "exportedAt": "2023-11-14T22:13:20Z",
            "futureField": "should be ignored",
            "annotations": [
                {
                    "id": "550E8400-E29B-41D4-A716-446655440000",
                    "type": "highlight",
                    "selectedText": "Hello",
                    "createdAt": "2023-11-14T22:13:20Z",
                    "updatedAt": "2023-11-14T22:13:20Z",
                    "unknownAnnotationField": 42
                }
            ]
        }
        """
        let data = Data(json.utf8)

        let result = try VReaderAnnotationParser.parse(data: data)

        #expect(result.annotations.count == 1)
        #expect(result.annotations.first?.selectedText == "Hello")
    }

    // MARK: - Unicode / CJK

    @Test func unicodeContent_preserved() throws {
        let h = makeExportedHighlight(text: "Unicode: \u{1F4DA} \u{2764}")
        let data = try encode(makePayload(annotations: [h]))

        let result = try VReaderAnnotationParser.parse(data: data)
        let annotation = try #require(result.annotations.first)

        #expect(annotation.selectedText == "Unicode: \u{1F4DA} \u{2764}")
    }

    @Test func cjkContent_preserved() throws {
        let h = makeExportedHighlight(text: "中文高亮测试")
        let n = makeExportedNote(content: "日本語のメモ")
        let data = try encode(makePayload(
            annotations: [h, n],
            bookTitle: "中文书名",
            bookAuthor: "作者"
        ))

        let result = try VReaderAnnotationParser.parse(data: data)

        #expect(result.bookTitle == "中文书名")
        #expect(result.bookAuthor == "作者")
        #expect(result.annotations[0].selectedText == "中文高亮测试")
        #expect(result.annotations[1].note == "日本語のメモ")
    }

    // MARK: - Nil Optional Fields

    @Test func nilOptionalFields_handledCorrectly() throws {
        let annotation = ExportedAnnotation(
            id: UUID(), type: .highlight, chapter: nil,
            selectedText: nil, note: nil, color: nil, title: nil,
            createdAt: fixedDate, updatedAt: fixedDate
        )
        let data = try encode(makePayload(annotations: [annotation]))

        let result = try VReaderAnnotationParser.parse(data: data)
        let parsed = try #require(result.annotations.first)

        #expect(parsed.chapter == nil)
        #expect(parsed.selectedText == nil)
        #expect(parsed.note == nil)
        #expect(parsed.color == nil)
        #expect(parsed.title == nil)
    }
}
