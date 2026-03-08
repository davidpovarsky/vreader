// Purpose: Splits large text into rendering chunks at paragraph boundaries.
// Used by the chunked TXT reader to feed one chunk per UITableView cell,
// avoiding full-document NSAttributedString allocation.
//
// Key decisions:
// - Splits at newline boundaries for clean paragraph breaks.
// - Falls back to character-boundary splitting for very long lines without newlines.
// - Preserves all content exactly — joined chunks == original text.
// - Target chunk size is in UTF-16 code units (matching NSString/UIKit conventions).
//
// @coordinates-with: TXTReaderContainerView.swift, TXTChunkedReaderBridge.swift

import Foundation

enum TXTTextChunker {

    /// Splits text into chunks of approximately `targetChunkSize` UTF-16 code units.
    /// Chunks split at newline boundaries when possible, falling back to hard splits
    /// for lines longer than the target.
    ///
    /// - Parameters:
    ///   - text: The full text to split.
    ///   - targetChunkSize: Target size per chunk in UTF-16 code units. Default 16384.
    /// - Returns: Array of text chunks. Joined, they equal the original text.
    static func split(text: String, targetChunkSize: Int = 16384) -> [String] {
        guard !text.isEmpty else { return [] }
        let target = max(targetChunkSize, 1)

        var chunks: [String] = []
        var currentChunk = ""
        var currentSize = 0

        // Scan through text splitting at newline boundaries
        var index = text.startIndex
        while index < text.endIndex {
            // Find the next newline (or end of string)
            let lineEnd: String.Index
            let afterLine: String.Index
            if let newlineRange = text.range(of: "\n", range: index..<text.endIndex) {
                lineEnd = newlineRange.upperBound  // include the newline in the line
                afterLine = newlineRange.upperBound
            } else {
                lineEnd = text.endIndex
                afterLine = text.endIndex
            }

            let line = text[index..<lineEnd]
            let lineSize = line.utf16.count

            // If adding this line would exceed target, flush current chunk first
            if currentSize > 0 && currentSize + lineSize > target {
                chunks.append(currentChunk)
                currentChunk = ""
                currentSize = 0
            }

            // If a single line is longer than target, hard-split it
            if lineSize > target {
                var lineIdx = line.startIndex
                while lineIdx < line.endIndex {
                    let remaining = line[lineIdx..<line.endIndex]
                    let piece = remaining.prefix(target - currentSize > 0 ? target - currentSize : target)
                    let pieceSize = piece.utf16.count

                    currentChunk += piece
                    currentSize += pieceSize
                    lineIdx = piece.endIndex

                    if currentSize >= target {
                        chunks.append(currentChunk)
                        currentChunk = ""
                        currentSize = 0
                    }
                }
            } else {
                currentChunk += line
                currentSize += lineSize
            }

            index = afterLine
        }

        // Flush any remaining content
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }
}
