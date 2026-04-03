// Purpose: Protocol and concrete implementations for book metadata extraction.
// EPUBMetadataExtractor reads OPF metadata (title, author) and extracts cover
// image bytes from the EPUB ZIP archive. AZW3MetadataExtractor delegates cover
// extraction to MOBICoverExtractor (native PDB/MOBI header parsing).
// Other formats use filename-based stubs.
//
// Key decisions:
// - Protocol-based design allows easy testing with mocks.
// - extractCoverImage has a default nil implementation (opt-in per format).
// - EPUBMetadataExtractor is stateless: each method opens the ZIP independently.
// - Cover extraction is fast (<50ms) — lightweight OPF-only parse + single entry read.
//
// @coordinates-with: BookImporter.swift, EPUBParser.swift, ZIPReader.swift,
//   CustomCoverStore.swift, MOBICoverExtractor.swift

import Foundation
import UIKit

/// Maximum title length in characters (shared across all extractors).
private let maxTitleLength = 255

/// Extracted metadata from a book file.
struct BookMetadata: Sendable, Equatable {
    /// Book title (required).
    let title: String

    /// Author name (optional).
    let author: String?

    /// Relative path to extracted cover image (optional).
    let coverImagePath: String?

    /// Creates metadata using filename-derived title (shared default behavior).
    static func fromFilename(_ fileURL: URL, author: String? = nil, coverImagePath: String? = nil) -> BookMetadata {
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        // Guard against dot-prefixed names with no real extension (e.g., ".txt"
        // is treated by URL as a hidden file, not "stem.ext"). If pathExtension
        // is empty and the name starts with ".", there is no meaningful stem.
        let hasNoStem = trimmed.isEmpty
            || (fileURL.pathExtension.isEmpty && trimmed.hasPrefix("."))
        let title = hasNoStem ? "Untitled" : String(trimmed.prefix(maxTitleLength))
        return BookMetadata(title: title, author: author, coverImagePath: coverImagePath)
    }
}

/// Protocol for extracting metadata from book files.
protocol MetadataExtractor: Sendable {
    /// Extracts metadata from the file at the given URL.
    ///
    /// - Parameter fileURL: Path to the imported file in sandbox.
    /// - Returns: Extracted metadata.
    func extractMetadata(from fileURL: URL) async throws -> BookMetadata

    /// Extracts the cover image from the file at the given URL, if available.
    /// Default implementation returns nil (no cover). Formats that support embedded
    /// covers (EPUB, AZW3) override this.
    ///
    /// - Parameter fileURL: Path to the book file.
    /// - Returns: The cover image, or nil if unavailable or not decodable.
    func extractCoverImage(from fileURL: URL) async -> UIImage?
}

extension MetadataExtractor {
    func extractCoverImage(from fileURL: URL) async -> UIImage? { nil }
}

/// Extracts metadata for TXT files. Title from filename, no author, no cover.
struct TXTMetadataExtractor: MetadataExtractor {
    func extractMetadata(from fileURL: URL) async throws -> BookMetadata {
        .fromFilename(fileURL)
    }
}

/// Extracts metadata and cover image from EPUB files.
/// Opens the EPUB as a ZIP, parses container.xml -> OPF for metadata/cover href,
/// then extracts the cover image entry. Stateless: each method opens the ZIP
/// independently for simplicity and thread safety.
struct EPUBMetadataExtractor: MetadataExtractor {

    func extractMetadata(from fileURL: URL) async throws -> BookMetadata {
        guard let (metadata, _) = try? await Self.parseEPUBMetadata(from: fileURL) else {
            return .fromFilename(fileURL)
        }
        return BookMetadata(
            title: String(metadata.title.prefix(maxTitleLength)),
            author: metadata.author,
            coverImagePath: nil
        )
    }

    func extractCoverImage(from fileURL: URL) async -> UIImage? {
        guard let (metadata, opfDirPath) = try? await Self.parseEPUBMetadata(from: fileURL),
              let coverHref = metadata.coverImageHref else {
            return nil
        }

        // Resolve cover path relative to OPF directory within the archive.
        let archivePath = Self.resolveArchivePath(coverHref: coverHref, opfDirPath: opfDirPath)

        guard let zip = try? ZIPReader(fileURL: fileURL),
              let entry = await zip.entry(forPath: archivePath),
              let imageData = try? await zip.extractData(for: entry) else {
            return nil
        }

        return UIImage(data: imageData)
    }

    // MARK: - Private

    /// Parses container.xml and OPF from an EPUB ZIP archive.
    /// Returns the parsed EPUBMetadata and the OPF directory path within the archive.
    private static func parseEPUBMetadata(from fileURL: URL) async throws -> (EPUBMetadata, String) {
        let zip = try ZIPReader(fileURL: fileURL)

        // Extract container.xml data
        guard let containerEntry = await zip.entry(forPath: "META-INF/container.xml") else {
            throw EPUBParserError.invalidFormat("No META-INF/container.xml")
        }
        let containerData = try await zip.extractData(for: containerEntry)
        let opfRelPath = try EPUBParser.parseContainerXML(containerData)

        // Extract and parse OPF
        guard let opfEntry = await zip.entry(forPath: opfRelPath) else {
            throw EPUBParserError.invalidFormat("OPF not found at \(opfRelPath)")
        }
        let opfData = try await zip.extractData(for: opfEntry)
        let result = try EPUBParser.parseOPF(opfData)

        let opfDirPath = (opfRelPath as NSString).deletingLastPathComponent
        return (result.metadata, opfDirPath)
    }

    /// Resolves a cover image href relative to the OPF directory within the archive.
    /// Handles ../ path components and produces a clean archive path.
    ///
    /// Examples:
    /// - opfDirPath="OEBPS", coverHref="Images/cover.jpg" -> "OEBPS/Images/cover.jpg"
    /// - opfDirPath="OEBPS", coverHref="../cover.jpg" -> "cover.jpg"
    /// - opfDirPath="", coverHref="cover.jpg" -> "cover.jpg"
    static func resolveArchivePath(coverHref: String, opfDirPath: String) -> String {
        guard !opfDirPath.isEmpty else { return coverHref }

        let combined = "\(opfDirPath)/\(coverHref)"
        let parts = combined.components(separatedBy: "/")

        var resolved: [String] = []
        for part in parts {
            if part == ".." {
                if !resolved.isEmpty { resolved.removeLast() }
            } else if part != "." && !part.isEmpty {
                resolved.append(part)
            }
        }

        return resolved.joined(separator: "/")
    }
}

/// Stub extractor for PDF files.
/// TODO(WI-7): Replace with PDFKit-based extractor that reads PDF document info
/// (title, author, page count). Remove this stub when WI-7 lands.
struct PDFMetadataExtractor: MetadataExtractor {
    func extractMetadata(from fileURL: URL) async throws -> BookMetadata {
        .fromFilename(fileURL)
    }
}

/// Extractor for AZW3/MOBI files. Title from filename (EXTH title parsing is
/// out of scope). Cover image is extracted by native MOBI header parsing.
struct AZW3MetadataExtractor: MetadataExtractor {
    func extractMetadata(from fileURL: URL) async throws -> BookMetadata {
        .fromFilename(fileURL)
    }

    func extractCoverImage(from fileURL: URL) async -> UIImage? {
        MOBICoverExtractor.extractCover(from: fileURL)
    }
}
