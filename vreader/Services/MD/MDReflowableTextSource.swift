// Purpose: Adapter that wraps a Markdown file's rendered text into
// the ReflowableTextSource protocol. Created after MDReaderViewModel.open()
// completes. Provides a single segment for the rendered text.
//
// Key decisions:
// - Single segment for the full rendered text (like TXT adapter).
// - Empty rendered text produces zero segments.
// - Standalone adapter: does NOT modify MDReaderViewModel.
// - Uses rendered (plain) text, not the raw markdown source.
//
// @coordinates-with: ReflowableTextSource.swift, MDReaderViewModel.swift

import Foundation

/// Adapts rendered Markdown text into the ReflowableTextSource protocol.
/// For MD files, the entire rendered text is a single segment.
struct MDReflowableTextSource: ReflowableTextSource {

    /// All text segments. For MD, this is either empty (for empty text)
    /// or a single segment containing the full rendered text.
    let segments: [TextSegment]

    /// Total rendered text length in UTF-16 code units.
    let totalLengthUTF16: Int

    /// The full rendered text content.
    let fullText: String

    /// Creates an MD text source from rendered text.
    /// - Parameter renderedText: The rendered plain text from the Markdown parser.
    init(renderedText: String) {
        self.fullText = renderedText
        let length = renderedText.utf16.count
        self.totalLengthUTF16 = length

        if length > 0 {
            self.segments = [
                TextSegment(
                    text: renderedText,
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
