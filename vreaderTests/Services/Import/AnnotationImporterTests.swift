// Purpose: Tests for AnnotationImporter — imports VReader JSON exports into
// the persistence layer via mock stores. Covers deduplication, error handling,
// progress reporting, and edge cases.
//
// @coordinates-with: AnnotationImporter.swift, VReaderAnnotationParser.swift,
//   MockHighlightStore.swift, MockBookmarkStore.swift, MockAnnotationStore.swift

import Testing
import Foundation
@testable import vreader

/// Thread-safe progress value collector for testing async progress callbacks.
private actor ProgressCollector {
    var values: [Double] = []
    func append(_ value: Double) { values.append(value) }
}

@Suite("AnnotationImporter")
struct AnnotationImporterTests {

    // MARK: - Helpers

    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private let testFingerprintKey = "epub:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890:2048"

    private func encode(_ payload: AnnotationExportPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

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

    private func makeHighlightAnnotation(
        id: UUID = UUID(),
        text: String = "Highlighted text",
        note: String? = nil,
        color: String? = "yellow",
        chapter: String? = nil
    ) -> ExportedAnnotation {
        ExportedAnnotation(
            id: id, type: .highlight, chapter: chapter,
            selectedText: text, note: note, color: color, title: nil,
            createdAt: fixedDate, updatedAt: fixedDate
        )
    }

    private func makeBookmarkAnnotation(
        id: UUID = UUID(),
        title: String? = "Bookmark",
        chapter: String? = nil
    ) -> ExportedAnnotation {
        ExportedAnnotation(
            id: id, type: .bookmark, chapter: chapter,
            selectedText: nil, note: nil, color: nil, title: title,
            createdAt: fixedDate, updatedAt: fixedDate
        )
    }

    private func makeNoteAnnotation(
        id: UUID = UUID(),
        content: String = "A note",
        chapter: String? = nil
    ) -> ExportedAnnotation {
        ExportedAnnotation(
            id: id, type: .note, chapter: chapter,
            selectedText: nil, note: content, color: nil, title: nil,
            createdAt: fixedDate, updatedAt: fixedDate
        )
    }

    private func makeImporter(
        highlights: MockHighlightStore = MockHighlightStore(),
        bookmarks: MockBookmarkStore = MockBookmarkStore(),
        annotations: MockAnnotationStore = MockAnnotationStore(),
        existingIds: Set<UUID> = []
    ) -> AnnotationImporter {
        AnnotationImporter(
            highlightStore: highlights,
            bookmarkStore: bookmarks,
            annotationStore: annotations,
            existingAnnotationIds: existingIds
        )
    }

    // MARK: - Import Highlights

    @Test func importVReaderJSON_createsHighlights() async throws {
        let h1 = makeHighlightAnnotation(text: "First highlight")
        let h2 = makeHighlightAnnotation(text: "Second highlight", note: "With note", color: "#ff0000")
        let data = try encode(makePayload(annotations: [h1, h2]))

        let highlights = MockHighlightStore()
        let importer = makeImporter(highlights: highlights)
        let result = try await importer.importJSON(data: data, bookFingerprintKey: testFingerprintKey)

        #expect(result.importedCount == 2)
        #expect(result.skippedCount == 0)
        let stored = await highlights.allHighlights()
        #expect(stored.count == 2)
    }

    // MARK: - Import Bookmarks

    @Test func importVReaderJSON_createsBookmarks() async throws {
        let b1 = makeBookmarkAnnotation(title: "Page 42")
        let b2 = makeBookmarkAnnotation(title: "Important Section")
        let data = try encode(makePayload(annotations: [b1, b2]))

        let bookmarks = MockBookmarkStore()
        let importer = makeImporter(bookmarks: bookmarks)
        let result = try await importer.importJSON(data: data, bookFingerprintKey: testFingerprintKey)

        #expect(result.importedCount == 2)
        let stored = await bookmarks.allBookmarks()
        #expect(stored.count == 2)
    }

    // MARK: - Import Notes

    @Test func importVReaderJSON_createsNotes() async throws {
        let n = makeNoteAnnotation(content: "My imported note")
        let data = try encode(makePayload(annotations: [n]))

        let annotations = MockAnnotationStore()
        let importer = makeImporter(annotations: annotations)
        let result = try await importer.importJSON(data: data, bookFingerprintKey: testFingerprintKey)

        #expect(result.importedCount == 1)
        let stored = await annotations.allAnnotations()
        #expect(stored.count == 1)
    }

    // MARK: - Duplicate ID Skips

    @Test func importVReaderJSON_duplicateId_skips() async throws {
        let existingId = UUID()
        let h = makeHighlightAnnotation(id: existingId, text: "Already exists")
        let h2 = makeHighlightAnnotation(text: "New one")
        let data = try encode(makePayload(annotations: [h, h2]))

        let highlights = MockHighlightStore()
        let importer = makeImporter(highlights: highlights, existingIds: [existingId])
        let result = try await importer.importJSON(data: data, bookFingerprintKey: testFingerprintKey)

        #expect(result.importedCount == 1)
        #expect(result.skippedCount == 1)
        let stored = await highlights.allHighlights()
        #expect(stored.count == 1)
    }

    @Test func importVReaderJSON_allDuplicates_noneImported() async throws {
        let id1 = UUID()
        let id2 = UUID()
        let h1 = makeHighlightAnnotation(id: id1, text: "Dup 1")
        let h2 = makeBookmarkAnnotation(id: id2, title: "Dup 2")
        let data = try encode(makePayload(annotations: [h1, h2]))

        let importer = makeImporter(existingIds: [id1, id2])
        let result = try await importer.importJSON(data: data, bookFingerprintKey: testFingerprintKey)

        #expect(result.importedCount == 0)
        #expect(result.skippedCount == 2)
    }

    // MARK: - Malformed JSON

    @Test func importVReaderJSON_malformedJSON_returnsError() async {
        let garbage = Data("not json".utf8)
        let importer = makeImporter()

        do {
            _ = try await importer.importJSON(data: garbage, bookFingerprintKey: testFingerprintKey)
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is AnnotationImportError)
        }
    }

    // MARK: - Empty Array

    @Test func importVReaderJSON_emptyArray_noOp() async throws {
        let data = try encode(makePayload(annotations: []))

        let highlights = MockHighlightStore()
        let bookmarks = MockBookmarkStore()
        let annotations = MockAnnotationStore()
        let importer = makeImporter(highlights: highlights, bookmarks: bookmarks, annotations: annotations)
        let result = try await importer.importJSON(data: data, bookFingerprintKey: testFingerprintKey)

        #expect(result.importedCount == 0)
        #expect(result.skippedCount == 0)
        let h = await highlights.addCallCount
        let b = await bookmarks.addCallCount
        let a = await annotations.addCallCount
        #expect(h == 0)
        #expect(b == 0)
        #expect(a == 0)
    }

    // MARK: - Future Fields Ignored

    @Test func importVReaderJSON_futureFields_ignored() async throws {
        let json = """
        {
            "bookTitle": "Future Book",
            "bookAuthor": "Author",
            "exportedAt": "2023-11-14T22:13:20Z",
            "newFieldV3": true,
            "annotations": [
                {
                    "id": "550E8400-E29B-41D4-A716-446655440000",
                    "type": "highlight",
                    "selectedText": "Hello future",
                    "createdAt": "2023-11-14T22:13:20Z",
                    "updatedAt": "2023-11-14T22:13:20Z",
                    "futureAnnotationField": [1, 2, 3]
                }
            ]
        }
        """
        let data = Data(json.utf8)

        let highlights = MockHighlightStore()
        let importer = makeImporter(highlights: highlights)
        let result = try await importer.importJSON(data: data, bookFingerprintKey: testFingerprintKey)

        #expect(result.importedCount == 1)
        let stored = await highlights.allHighlights()
        #expect(stored.count == 1)
    }

    // MARK: - ISO 8601 Dates

    @Test func importVReaderJSON_datesParsed_ISO8601() async throws {
        let h = makeHighlightAnnotation(text: "Date test")
        let data = try encode(makePayload(annotations: [h]))

        let highlights = MockHighlightStore()
        let importer = makeImporter(highlights: highlights)
        _ = try await importer.importJSON(data: data, bookFingerprintKey: testFingerprintKey)

        let stored = await highlights.allHighlights()
        // The highlight was created via the mock, which assigns Date() — but the
        // payload was parsed successfully from ISO 8601 format (tested in parser tests).
        // Here we verify the import completed without date parsing errors.
        #expect(stored.count == 1)
    }

    // MARK: - Progress Reporting

    @Test func importProgress_reportsCorrectly() async throws {
        let items: [ExportedAnnotation] = (0..<5).map { i in
            makeHighlightAnnotation(text: "Item \(i)")
        }
        let data = try encode(makePayload(annotations: items))

        let collector = ProgressCollector()
        let highlights = MockHighlightStore()
        let importer = makeImporter(highlights: highlights)

        _ = try await importer.importJSON(
            data: data,
            bookFingerprintKey: testFingerprintKey,
            onProgress: { progress in
                Task { await collector.append(progress) }
            }
        )

        // Small delay to let Task-wrapped appends complete
        try await Task.sleep(for: .milliseconds(50))

        let progressValues = await collector.values
        // Should report progress for each item
        #expect(progressValues.count == 5)
        // First progress should be 1/5 = 0.2
        #expect(progressValues.first == 0.2)
        // Last progress should be 5/5 = 1.0
        #expect(progressValues.last == 1.0)
        // Progress should be monotonically increasing
        for i in 1..<progressValues.count {
            #expect(progressValues[i] > progressValues[i - 1])
        }
    }

    @Test func importProgress_noCallback_stillWorks() async throws {
        let h = makeHighlightAnnotation(text: "No progress callback")
        let data = try encode(makePayload(annotations: [h]))

        let highlights = MockHighlightStore()
        let importer = makeImporter(highlights: highlights)
        let result = try await importer.importJSON(data: data, bookFingerprintKey: testFingerprintKey)

        #expect(result.importedCount == 1)
    }

    // MARK: - Mixed Types

    @Test func importMixedTypes_allCreated() async throws {
        let h = makeHighlightAnnotation(text: "Highlight")
        let b = makeBookmarkAnnotation(title: "Bookmark")
        let n = makeNoteAnnotation(content: "Note")
        let data = try encode(makePayload(annotations: [h, b, n]))

        let highlights = MockHighlightStore()
        let bookmarks = MockBookmarkStore()
        let annotations = MockAnnotationStore()
        let importer = makeImporter(highlights: highlights, bookmarks: bookmarks, annotations: annotations)
        let result = try await importer.importJSON(data: data, bookFingerprintKey: testFingerprintKey)

        #expect(result.importedCount == 3)
        #expect(result.skippedCount == 0)
        let h_count = await highlights.allHighlights().count
        let b_count = await bookmarks.allBookmarks().count
        let a_count = await annotations.allAnnotations().count
        #expect(h_count == 1)
        #expect(b_count == 1)
        #expect(a_count == 1)
    }

    // MARK: - Empty Data

    @Test func importEmptyData_throwsError() async {
        let importer = makeImporter()

        do {
            _ = try await importer.importJSON(data: Data(), bookFingerprintKey: testFingerprintKey)
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is AnnotationImportError)
        }
    }
}
