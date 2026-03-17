// Purpose: Codable DTO for annotation export. Captures highlights, bookmarks,
// and notes in a format-agnostic structure suitable for JSON/Markdown/PDF export.
//
// Key decisions:
// - All date fields use ISO 8601 encoding for interoperability.
// - Chapter is optional — annotations without chapter info go to "Ungrouped".
// - Color is stored as-is (hex or name) from the source HighlightRecord.
// - Sendable for cross-actor safety.
//
// @coordinates-with: AnnotationExporter.swift, MarkdownExportFormatter.swift,
//   JSONExportFormatter.swift

import Foundation

/// The kind of annotation being exported.
enum ExportedAnnotationType: String, Codable, Sendable {
    case highlight
    case bookmark
    case note
}

/// A single exported annotation, combining data from highlights, bookmarks, and notes.
struct ExportedAnnotation: Codable, Sendable, Equatable {
    let id: UUID
    let type: ExportedAnnotationType
    let chapter: String?
    let selectedText: String?
    let note: String?
    let color: String?
    let title: String?
    let createdAt: Date
    let updatedAt: Date
}

/// Container for a full annotation export, including book metadata.
struct AnnotationExportPayload: Codable, Sendable, Equatable {
    let bookTitle: String
    let bookAuthor: String?
    let exportedAt: Date
    let annotations: [ExportedAnnotation]
}
