// Purpose: Protocol defining a unified text source for reflowable content.
// Consumed by TTS (Phase B) and unified paginator (Phase B). Provides
// segmented text with UTF-16 offsets matching UIKit/TextKit conventions.
//
// Key decisions:
// - Segments use UTF-16 offsets to match NSString/UIKit/TextKit conventions.
// - TextSegment is a value type (struct, Sendable, Equatable) for safe passing.
// - segmentContaining(offsetUTF16:) returns nil for out-of-range offsets.
// - Protocol is not @MainActor — adapters may be, but the protocol itself is
//   usable from any context via nonisolated computed properties.
//
// @coordinates-with: TXTReflowableTextSource.swift, MDReflowableTextSource.swift

import Foundation

/// A contiguous segment of text with its UTF-16 offset within the full document.
struct TextSegment: Sendable, Equatable {
    /// The text content of this segment.
    let text: String
    /// The starting UTF-16 offset of this segment within the full document.
    let startOffsetUTF16: Int
    /// The length of this segment in UTF-16 code units.
    let lengthUTF16: Int
}

/// Protocol for providing reflowable text content as a sequence of segments
/// with UTF-16 offsets. Used by TTS and pagination consumers.
protocol ReflowableTextSource {
    /// All text segments, ordered by offset. Concatenation equals `fullText`.
    var segments: [TextSegment] { get }
    /// Total text length in UTF-16 code units.
    var totalLengthUTF16: Int { get }
    /// The full text content (concatenation of all segments).
    var fullText: String { get }
    /// Returns the segment containing the given UTF-16 offset, or nil if out of range.
    /// Valid offsets are in the range [0, totalLengthUTF16). Offset == totalLengthUTF16
    /// is past-end and returns nil.
    func segmentContaining(offsetUTF16: Int) -> TextSegment?
}
