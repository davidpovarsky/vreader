// Purpose: Protocol for TXT file loading, encoding detection, and content access.
// Decouples the reader ViewModel from file I/O for testability.
//
// Key decisions:
// - Async throws for all I/O operations.
// - Sendable for safe cross-actor usage.
// - Returns decoded string content and metadata (byte count, encoding).
// - open/close lifecycle mirrors EPUBParserProtocol pattern.
// - totalWordCount and totalTextLengthUTF16 provided for wordsRead estimation.
// - Chapter-based open path (WI-5) returns index + loader without full decode.
//
// @coordinates-with: TXTReaderViewModel.swift, TXTChunkedLoader.swift, TXTOffsetMapper.swift,
//   TXTChapterIndex.swift, TXTChapterContentLoader.swift

import Foundation

/// Errors that can occur during TXT file loading.
enum TXTServiceError: Error, Sendable, Equatable {
    case fileNotFound(String)
    case encodingDetectionFailed(String)
    case decodingFailed(String)
    case notOpen
    case alreadyOpen
}

/// Metadata about a loaded TXT file.
struct TXTFileMetadata: Sendable, Equatable {
    /// The decoded full text content.
    let text: String
    /// Total byte count of the source file.
    let fileByteCount: Int64
    /// Detected or specified encoding name (e.g., "UTF-8", "Shift_JIS").
    let detectedEncoding: String
    /// Total text length in UTF-16 code units.
    let totalTextLengthUTF16: Int
    /// Total word count (whitespace-split, locale-independent).
    let totalWordCount: Int
}

/// Result of chapter-based file open (WI-5).
/// Contains everything needed to display the first chapter without full-file decode.
struct TXTChapterOpenResult: Sendable {
    /// Chapter index covering the entire file.
    let chapterIndex: TXTChapterIndex
    /// Content loader for on-demand chapter access (actor-isolated, 3-chapter LRU cache).
    let contentLoader: TXTChapterContentLoader
    /// Total file size in bytes.
    let fileByteCount: Int64
    /// Detected encoding name (e.g. "UTF-8", "GBK").
    let detectedEncoding: String
}

/// Protocol for TXT file loading operations.
/// In production, backed by file I/O + encoding detection. In tests, backed by a mock.
protocol TXTServiceProtocol: Sendable {
    /// Opens and decodes a TXT file at the given URL.
    func open(url: URL) async throws -> TXTFileMetadata

    /// Opens the file using chapter-based lazy loading (Legado pattern).
    /// Returns chapter index + metadata WITHOUT decoding the full file.
    /// Only detects encoding + builds chapter index from streaming blocks.
    func openChapterBased(url: URL) async throws -> TXTChapterOpenResult

    /// Closes the currently open file and releases resources.
    func close() async

    /// Whether a file is currently open.
    var isOpen: Bool { get async }
}
