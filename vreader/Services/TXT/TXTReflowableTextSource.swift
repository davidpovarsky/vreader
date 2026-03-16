// Purpose: Adapter that wraps a TXT file's decoded text content into
// the ReflowableTextSource protocol. Created after TXTReaderViewModel.open()
// completes. Provides a single segment for the full text.
//
// Key decisions:
// - Single segment for the full text (TXT has no internal structure).
// - Empty text produces zero segments (not a single empty segment).
// - Standalone adapter: does NOT modify TXTReaderViewModel.
// - UTF-16 lengths computed once at init for consistency.
//
// @coordinates-with: ReflowableTextSource.swift, TXTReaderViewModel.swift

import Foundation

/// Adapts a plain text string into the ReflowableTextSource protocol.
/// For TXT files, the entire text is a single segment.
struct TXTReflowableTextSource: ReflowableTextSource {

    /// All text segments. For TXT, this is either empty (for empty text)
    /// or a single segment containing the full text.
    let segments: [TextSegment]

    /// Total text length in UTF-16 code units.
    let totalLengthUTF16: Int

    /// The full text content.
    let fullText: String

    /// Creates a TXT text source from decoded text content.
    /// - Parameter textContent: The full decoded text from the TXT file.
    init(textContent: String) {
        self.fullText = textContent
        let length = textContent.utf16.count
        self.totalLengthUTF16 = length

        if length > 0 {
            self.segments = [
                TextSegment(
                    text: textContent,
                    startOffsetUTF16: 0,
                    lengthUTF16: length
                )
            ]
        } else {
            self.segments = []
        }
    }

    /// Returns the segment containing the given UTF-16 offset, or nil if out of range.
    func segmentContaining(offsetUTF16: Int) -> TextSegment? {
        guard offsetUTF16 >= 0, offsetUTF16 < totalLengthUTF16 else { return nil }
        // Single segment: if offset is valid, it's always the first segment.
        return segments.first
    }
}
