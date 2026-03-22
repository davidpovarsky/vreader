// Purpose: Formats AnnotationExportPayload as human-readable Markdown.
// Groups highlights by chapter, includes notes and bookmarks.
//
// Format:
//   # Book Title
//   *by Author*
//
//   ## Chapter Name
//
//   > highlighted text
//
//   *Note: user's note*
//
//   ---
//
// @coordinates-with: AnnotationExporter.swift, ExportedAnnotation.swift

import Foundation

/// Formats annotations as Markdown text.
struct MarkdownExportFormatter: ExportFormatter {

    func format(_ payload: AnnotationExportPayload) throws -> Data {
        var lines: [String] = []

        // Title
        lines.append("# \(payload.bookTitle)")
        if let author = payload.bookAuthor {
            lines.append("*by \(author)*")
        }
        lines.append("")

        // Group annotations by chapter
        let grouped = Dictionary(grouping: payload.annotations) { $0.chapter ?? "" }
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            if lhs.isEmpty { return false }
            if rhs.isEmpty { return true }
            return lhs < rhs
        }

        for key in sortedKeys {
            guard let items = grouped[key] else { continue }

            if key.isEmpty {
                lines.append("## Ungrouped")
            } else {
                lines.append("## \(key)")
            }
            lines.append("")

            for item in items {
                switch item.type {
                case .highlight:
                    if let text = item.selectedText {
                        lines.append("> \(text)")
                        lines.append("")
                    }
                    if let note = item.note {
                        lines.append("*Note: \(note)*")
                        lines.append("")
                    }

                case .bookmark:
                    let label = item.title ?? "Bookmark"
                    lines.append("- \(label)")
                    lines.append("")

                case .note:
                    if let note = item.note {
                        lines.append("*Note: \(note)*")
                        lines.append("")
                    }
                }
            }
        }

        // If no annotations, produce minimal output
        if payload.annotations.isEmpty {
            lines.append("*No annotations.*")
            lines.append("")
        }

        let result = lines.joined(separator: "\n")
        guard let data = result.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        return data
    }
}

/// Errors that can occur during export.
enum ExportError: Error, Sendable {
    case encodingFailed
    case invalidFormat
}
