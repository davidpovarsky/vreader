// Purpose: Format-specific anchor for locating an annotation within a document.
// Supports EPUB (href + CFI + serialized DOM range), PDF (page + normalized rects),
// and plain text (source unit ID + UTF-16 offset range).
//
// Key decisions:
// - Codable enum with associated values — stored as JSON blob in SwiftData.
// - Sendable for cross-actor transfer (Swift 6 strict concurrency).
// - Equatable for deduplication and test assertions.
// - CGRect for PDF rects uses normalized page coordinates (0-1 range).
//
// @coordinates-with: Highlight.swift, HighlightRecord.swift, ReaderNotifications.swift

import Foundation
import CoreGraphics
import CryptoKit

/// Format-specific anchor for locating an annotation within a document.
enum AnnotationAnchor: Codable, Sendable, Equatable {
    /// EPUB: href identifies spine item, cfi for coarse location, serialized range for exact restore.
    case epub(href: String, cfi: String, serializedRange: EPUBSerializedRange)

    /// PDF: page index (0-based) + array of normalized rects (page coordinate space, 0-1 range).
    case pdf(page: Int, rects: [CGRect])

    /// TXT/MD: source unit ID + UTF-16 offset range.
    case text(sourceUnitId: String, startUTF16: Int, endUTF16: Int)

    // MARK: - Anchor Hash

    /// SHA-256 hash of the anchor's canonical JSON encoding.
    /// Used alongside locator's canonicalHash for highlight deduplication.
    var anchorHash: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Force-try is safe: AnnotationAnchor is always encodable.
        // swiftlint:disable:next force_try
        let data = try! encoder.encode(self)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Serialized DOM range for restoring an exact EPUB text selection.
struct EPUBSerializedRange: Codable, Sendable, Equatable {
    /// XPath to start container node.
    let startContainerPath: String
    let startOffset: Int
    /// XPath to end container node.
    let endContainerPath: String
    let endOffset: Int
}
