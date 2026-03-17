// Purpose: Structured errors for the annotation import pipeline.
//
// @coordinates-with: AnnotationImporter.swift, VReaderAnnotationParser.swift

import Foundation

/// Errors that can occur during annotation import.
enum AnnotationImportError: Error, Equatable, Sendable {
    /// The input data could not be parsed as valid VReader JSON.
    case invalidJSON(String)

    /// The input data is empty.
    case emptyData
}
