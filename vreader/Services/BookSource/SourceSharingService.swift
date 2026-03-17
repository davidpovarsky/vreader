// Purpose: Export/import single BookSource as Legado-compatible JSON,
// generate QR codes via CoreImage, and parse vreader:// URL schemes.
//
// Key decisions:
// - Reuses LegadoImporter for JSON serialization.
// - QR code via CIQRCodeGenerator (CoreImage, no external deps).
// - URL scheme: vreader://import-source?data=<base64 encoded JSON>.
//
// @coordinates-with: LegadoImporter.swift, BookSource.swift,
//   LegadoBookSourceDTO.swift

import Foundation
import UIKit
import CoreImage

/// Errors from source sharing operations.
enum SourceSharingError: Error, Sendable, Equatable {
    /// The URL scheme is not vreader://.
    case invalidScheme
    /// The URL host is not import-source.
    case invalidHost
    /// The data query parameter is missing.
    case missingData
    /// The base64 data could not be decoded.
    case invalidBase64
    /// The decoded data is not valid JSON.
    case invalidJSON
}

/// Exports and imports single BookSource objects for sharing.
///
/// Uses LegadoImporter for JSON serialization, CoreImage for QR generation,
/// and vreader:// URL scheme for one-tap import.
enum SourceSharingService {

    // MARK: - Constants

    /// URL scheme for VReader source import.
    private static let urlScheme = "vreader"

    /// URL host for source import action.
    private static let importHost = "import-source"

    /// Query parameter name for base64-encoded source data.
    private static let dataParam = "data"

    // MARK: - Export

    /// Exports a single BookSource as Legado-compatible JSON data.
    ///
    /// - Parameter source: The BookSource to export.
    /// - Returns: JSON data (always an array with one element).
    static func exportSource(_ source: BookSource) throws -> Data {
        try LegadoImporter.exportSources([source])
    }

    // MARK: - Import

    /// Imports BookSource objects from shared JSON data.
    ///
    /// - Parameter data: JSON data in Legado format.
    /// - Returns: Array of imported BookSource objects.
    static func importSource(from data: Data) throws -> [BookSource] {
        try LegadoImporter.importSources(from: data)
    }

    // MARK: - URL Scheme

    /// Generates a vreader:// URL string for sharing a source.
    ///
    /// Format: `vreader://import-source?data=<base64 encoded JSON>`
    ///
    /// - Parameter source: The BookSource to share.
    /// - Returns: A well-formed vreader:// URL string.
    static func generateSharingURL(for source: BookSource) throws -> String {
        let jsonData = try exportSource(source)
        let base64 = jsonData.base64EncodedString()
        return "\(urlScheme)://\(importHost)?\(dataParam)=\(base64)"
    }

    /// Parses a vreader://import-source URL and extracts BookSource objects.
    ///
    /// - Parameter url: The URL to parse.
    /// - Returns: Array of imported BookSource objects.
    /// - Throws: `SourceSharingError` on invalid URL format.
    static func parseImportURL(_ url: URL) throws -> [BookSource] {
        // Validate scheme
        guard url.scheme == urlScheme else {
            throw SourceSharingError.invalidScheme
        }

        // Validate host
        guard url.host == importHost else {
            throw SourceSharingError.invalidHost
        }

        // Extract data parameter
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataValue = components.queryItems?
                  .first(where: { $0.name == dataParam })?.value,
              !dataValue.isEmpty else {
            throw SourceSharingError.missingData
        }

        // Decode base64
        guard let jsonData = Data(base64Encoded: dataValue) else {
            throw SourceSharingError.invalidBase64
        }

        // Parse JSON via LegadoImporter
        return try importSource(from: jsonData)
    }

    // MARK: - QR Code

    /// Generates a QR code image (PNG data) for the given string.
    ///
    /// Uses CoreImage's CIQRCodeGenerator. Returns nil if the string
    /// is empty or QR generation fails.
    ///
    /// - Parameter string: The content to encode in the QR code.
    /// - Returns: PNG image data, or nil on failure.
    static func generateQRCode(for string: String) -> Data? {
        guard !string.isEmpty else { return nil }
        guard let data = string.data(using: .utf8) else { return nil }

        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter?.outputImage else { return nil }

        // Scale up for readability (QR output is tiny by default)
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: scale)

        let context = CIContext()
        guard let cgImage = context.createCGImage(
            scaledImage, from: scaledImage.extent
        ) else { return nil }

        return UIImage(cgImage: cgImage).pngData()
    }
}
