// Purpose: Protocol and dispatch for exporting annotations in multiple formats.
// Coordinates HighlightRecord, BookmarkRecord, and AnnotationRecord into
// ExportedAnnotation DTOs, then delegates to format-specific formatters.
//
// @coordinates-with: ExportedAnnotation.swift, MarkdownExportFormatter.swift,
//   JSONExportFormatter.swift

import Foundation

/// Supported export formats.
enum ExportFormat: String, Codable, Sendable, CaseIterable {
    case markdown
    case json
}

/// Protocol for format-specific export formatters.
protocol ExportFormatter: Sendable {
    /// Formats the payload into the target format's data representation.
    func format(_ payload: AnnotationExportPayload) throws -> Data
}

/// Builds an AnnotationExportPayload from raw records and dispatches to formatters.
enum AnnotationExporter {

    /// Builds export DTOs from raw records.
    /// - Parameters:
    ///   - highlights: Highlight records to export.
    ///   - bookmarks: Bookmark records to export.
    ///   - notes: Annotation (note) records to export.
    ///   - bookTitle: Title of the book.
    ///   - bookAuthor: Author of the book (optional).
    ///   - chapterMap: Maps locator href to chapter title for grouping.
    /// - Returns: An AnnotationExportPayload ready for formatting.
    static func buildPayload(
        highlights: [HighlightRecord],
        bookmarks: [BookmarkRecord],
        notes: [AnnotationRecord],
        bookTitle: String,
        bookAuthor: String?,
        chapterMap: [String: String] = [:]
    ) -> AnnotationExportPayload {
        var exported: [ExportedAnnotation] = []

        for h in highlights {
            let chapter = h.locator.href.flatMap { chapterMap[$0] }
            exported.append(ExportedAnnotation(
                id: h.highlightId,
                type: .highlight,
                chapter: chapter,
                selectedText: h.selectedText,
                note: h.note,
                color: h.color,
                title: nil,
                createdAt: h.createdAt,
                updatedAt: h.updatedAt
            ))
        }

        for b in bookmarks {
            let chapter = b.locator.href.flatMap { chapterMap[$0] }
            exported.append(ExportedAnnotation(
                id: b.bookmarkId,
                type: .bookmark,
                chapter: chapter,
                selectedText: nil,
                note: nil,
                color: nil,
                title: b.title,
                createdAt: b.createdAt,
                updatedAt: b.updatedAt
            ))
        }

        for n in notes {
            let chapter = n.locator.href.flatMap { chapterMap[$0] }
            exported.append(ExportedAnnotation(
                id: n.annotationId,
                type: .note,
                chapter: chapter,
                selectedText: nil,
                note: n.content,
                color: nil,
                title: nil,
                createdAt: n.createdAt,
                updatedAt: n.updatedAt
            ))
        }

        return AnnotationExportPayload(
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            exportedAt: Date(),
            annotations: exported
        )
    }

    /// Exports annotations in the specified format.
    static func export(
        payload: AnnotationExportPayload,
        format: ExportFormat
    ) throws -> Data {
        let formatter: ExportFormatter = switch format {
        case .markdown: MarkdownExportFormatter()
        case .json: JSONExportFormatter()
        }
        return try formatter.format(payload)
    }
}
