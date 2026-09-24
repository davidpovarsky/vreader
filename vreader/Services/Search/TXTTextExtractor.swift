// Purpose: Extracts text from TXT files for search indexing.
// Splits text into paragraph-based segments for snippet granularity.
//
// Key decisions:
// - Segments are paragraphs separated by double newlines (or single for short texts).
// - Each segment becomes a TextUnit with sourceUnitId "txt:segment:<N>".
// - Empty segments are filtered out to avoid indexing noise.
// - Segment text is NOT trimmed to preserve UTF-16 offset alignment with original text.
// - Also computes cumulative UTF-16 base offsets for locator resolution.
//
// @coordinates-with SearchTextExtractor.swift, TXTService.swift

import Foundation

/// Result of TXT text extraction, including segment base offsets for locator resolution.
struct TXTExtractionResult: Sendable {
    let textUnits: [TextUnit]
    /// Maps segment index → cumulative UTF-16 offset in the original text.
    let segmentBaseOffsets: [Int: Int]
}

/// Extracts text from TXT files for search indexing.
struct TXTTextExtractor: SearchTextExtractor {

    func extractTextUnits(
        from url: URL,
        fingerprint: DocumentFingerprint
    ) async throws -> [TextUnit] {
        let text = try Self.decodeFile(at: url)
        return segmentText(text).textUnits
    }

    /// Loads a file with encoding detection and extracts text units with offsets.
    /// Uses TXTService.decodeText() for encoding consistency with the reader display.
    func extractWithOffsets(from url: URL) async throws -> TXTExtractionResult {
        let text = try Self.decodeFile(at: url)
        return extractWithOffsets(from: text)
    }

    /// Bug #99 cause #2: decode via the unified `decodeForDisplayAndSearch`
    /// entry point so the search index uses the SAME bytes-to-String mapping
    /// (and therefore the same UTF-16 offsets) that `TXTService.open` /
    /// `openChapterBased` give the reader display. Pre-fix: this called
    /// `decodeText` directly, which skips the sample-hint path used by the
    /// display — for non-UTF-8 files where sample-detection and NSString
    /// heuristic could disagree, search hits landed on wrong characters
    /// because the offsets indexed differed from the offsets rendered.
    private static func decodeFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if let (text, _) = TXTService.decodeForDisplayAndSearch(data) {
            return text
        }
        throw TXTTextExtractorError.decodingFailed(
            "Could not decode file with any supported encoding"
        )
    }

    /// Creates text units from already-decoded text with segment base offsets.
    /// Useful when the text is already loaded (e.g., from TXTServiceProtocol).
    func extractWithOffsets(from text: String) -> TXTExtractionResult {
        segmentText(text)
    }

    /// Splits text into paragraph segments, tracking original UTF-16 offsets.
    /// Shared with Feature #177's TXT provider so search and AI navigation
    /// cannot drift on CRLF, emoji, or combining marks.
    private func segmentText(_ text: String) -> TXTExtractionResult {
        let segments = UTF16TextSegmenter.segments(in: text)
        return TXTExtractionResult(
            textUnits: segments.map {
                TextUnit(sourceUnitId: "txt:segment:\($0.index)", text: $0.text)
            },
            segmentBaseOffsets: Dictionary(
                uniqueKeysWithValues: segments.map { ($0.index, $0.startUTF16) }
            )
        )
    }
}

/// Errors during TXT text extraction.
enum TXTTextExtractorError: Error, Sendable {
    case decodingFailed(String)
}
