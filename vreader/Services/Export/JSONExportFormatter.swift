// Purpose: Formats AnnotationExportPayload as JSON with ISO 8601 dates.
// Output is designed for round-tripping — can be decoded back to the same payload.
//
// Key decisions:
// - Uses .iso8601 date strategy for interoperability.
// - Pretty-printed for readability.
// - Sorted keys for deterministic output.
//
// @coordinates-with: AnnotationExporter.swift, ExportedAnnotation.swift

import Foundation

/// Formats annotations as JSON data with ISO 8601 dates.
struct JSONExportFormatter: ExportFormatter {

    func format(_ payload: AnnotationExportPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }
}
