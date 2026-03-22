// Purpose: Parses VReader JSON export data into AnnotationExportPayload.
// Handles forward compatibility by ignoring unknown fields.
//
// @coordinates-with: ExportedAnnotation.swift, AnnotationImporter.swift,
//   JSONExportFormatter.swift

import Foundation

/// Parses VReader JSON annotation export format.
enum VReaderAnnotationParser {

    /// Parses JSON data into an AnnotationExportPayload.
    /// - Parameter data: JSON data in VReader export format.
    /// - Returns: The parsed payload.
    /// - Throws: `AnnotationImportError` if the data is invalid.
    static func parse(data: Data) throws -> AnnotationExportPayload {
        guard !data.isEmpty else {
            throw AnnotationImportError.emptyData
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AnnotationExportPayload.self, from: data)
        } catch let error as AnnotationImportError {
            throw error
        } catch {
            throw AnnotationImportError.invalidJSON(
                error is DecodingError
                    ? "Invalid VReader JSON format: \(error.localizedDescription)"
                    : String(describing: error)
            )
        }
    }
}
