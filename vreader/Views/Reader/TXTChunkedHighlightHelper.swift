// Purpose: Highlight helper methods for TXTChunkedReaderBridge.Coordinator —
// dynamic navigation (scroll-to-offset), highlight application/clearing,
// and chunk-local highlight range computation.
//
// @coordinates-with TXTChunkedReaderBridge.swift, HighlightableTextView.swift

#if canImport(UIKit)
import UIKit

extension TXTChunkedReaderBridge.Coordinator {

    // MARK: - Dynamic Navigation (Bug #52)

    /// Scrolls the table view to the chunk containing the given document-global
    /// UTF-16 offset, with intra-chunk positioning.
    func scrollToGlobalOffset(_ globalOffset: Int, in tableView: UITableView) {
        guard !chunkStartOffsets.isEmpty else { return }

        // Binary search for the chunk containing globalOffset
        var lo = 0, hi = chunkStartOffsets.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if chunkStartOffsets[mid] <= globalOffset {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        let chunkIndex = lo
        guard chunkIndex < chunks.count else { return }

        // Compute intra-chunk fraction for sub-cell positioning
        let chunkStart = chunkStartOffsets[chunkIndex]
        let nextStart = chunkIndex + 1 < chunkStartOffsets.count
            ? chunkStartOffsets[chunkIndex + 1]
            : chunkStart + chunks[chunkIndex].utf16.count
        let chunkLen = nextStart - chunkStart
        let fraction: CGFloat = chunkLen > 0
            ? CGFloat(globalOffset - chunkStart) / CGFloat(chunkLen)
            : 0

        attemptChunkRestore(in: tableView, toChunkIndex: chunkIndex, intraFraction: fraction)
    }

    // MARK: - Highlight (Bug #53)

    /// Applies a temporary yellow highlight to the given document-global range.
    /// Handles ranges within a single chunk. Ranges spanning chunk boundaries
    /// highlight from the start offset to the end of that chunk.
    func applyHighlight(_ globalRange: NSRange, in tableView: UITableView, isTemporary: Bool = true) {
        guard !chunkStartOffsets.isEmpty else { return }
        let globalStart = globalRange.location
        let globalEnd = globalRange.location + globalRange.length
        // Bug #47: Guard against invalid range values
        guard globalStart >= 0, globalEnd > globalStart else { return }

        // Find the chunk containing the highlight start
        var lo = 0, hi = chunkStartOffsets.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if chunkStartOffsets[mid] <= globalStart {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        let chunkIndex = lo
        guard chunkIndex < chunks.count else { return }
        let chunkStart = chunkStartOffsets[chunkIndex]

        // Convert to chunk-local range
        let localStart = globalStart - chunkStart
        guard localStart >= 0 else { return }
        let nextChunkStart = chunkIndex + 1 < chunkStartOffsets.count
            ? chunkStartOffsets[chunkIndex + 1]
            : chunkStart + chunks[chunkIndex].utf16.count
        let localEnd = min(globalEnd - chunkStart, nextChunkStart - chunkStart)
        let localLength = max(0, localEnd - localStart)
        guard localLength > 0 else { return }
        let localRange = NSRange(location: localStart, length: localLength)

        // Store active highlight for re-application on cell reuse (bug #54)
        activeHighlightChunkIndex = chunkIndex
        activeHighlightLocalRange = localRange

        // Rebuild the cell with highlight baked in (bug #47 v10)
        if let cell = tableView.cellForRow(at: IndexPath(row: chunkIndex, section: 0)) as? TXTChunkedReaderBridge.ChunkedTextCell {
            rebuildHighlightCell(cell, chunkIndex: chunkIndex)
        }

        // Only auto-clear temporary highlights (search navigation).
        // User-created highlights persist until replaced or navigated away (bug #54).
        highlightClearTimer?.invalidate()
        highlightClearTimer = nil
        if isTemporary {
            highlightClearTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self, weak tableView] _ in
                DispatchQueue.main.async {
                    guard let self, let tableView else { return }
                    self.activeHighlightChunkIndex = nil
                    self.activeHighlightLocalRange = nil
                    self.clearHighlight(in: tableView)
                    self.lastHighlightRange = nil
                }
            }
        }
    }

    /// Clears active highlight on visible cells via layout manager (bug #47 v12).
    /// NEVER modifies text storage — only updates highlight ranges for drawing.
    func clearHighlight(in tableView: UITableView) {
        highlightClearTimer?.invalidate()
        highlightClearTimer = nil
        for cell in tableView.visibleCells {
            guard let chunkedCell = cell as? TXTChunkedReaderBridge.ChunkedTextCell else { continue }
            let chunkIndex = chunkedCell.textContentView.tag
            let (persisted, _) = chunkLocalHighlightRanges(forChunk: chunkIndex)
            // Active highlight cleared — only pass persisted ranges
            chunkedCell.textContentView.setHighlightRanges(persisted: persisted, active: nil)
        }
    }

    /// Updates highlight ranges on the affected cell via layout manager (bug #47 v12).
    func rebuildHighlightCell(_ cell: TXTChunkedReaderBridge.ChunkedTextCell, chunkIndex: Int) {
        let (persisted, active) = chunkLocalHighlightRanges(forChunk: chunkIndex)
        cell.textContentView.setHighlightRanges(persisted: persisted, active: active)
    }

    /// Computes chunk-local highlight ranges for the layout manager (bug #47 v12).
    /// Returns persisted ranges + active range, all in chunk-local coordinates.
    func chunkLocalHighlightRanges(forChunk index: Int) -> (persisted: [NSRange], active: NSRange?) {
        guard index < chunkStartOffsets.count, index < chunks.count else { return ([], nil) }

        let chunkStart = chunkStartOffsets[index]
        let chunkEnd = index + 1 < chunkStartOffsets.count
            ? chunkStartOffsets[index + 1]
            : chunkStart + chunks[index].utf16.count
        let chunkTextLen = chunkEnd - chunkStart

        // Collect chunk-local persisted highlight ranges
        var localPersistedRanges: [NSRange] = []
        for globalRange in persistedHighlights {
            let globalStart = globalRange.location
            let globalEnd = globalRange.location + globalRange.length
            guard globalEnd > chunkStart, globalStart < chunkEnd else { continue }
            let localStart = max(0, globalStart - chunkStart)
            let localEnd = min(chunkEnd - chunkStart, globalEnd - chunkStart)
            let localLength = localEnd - localStart
            guard localLength > 0, localStart < chunkTextLen else { continue }
            let clampedLength = min(localLength, chunkTextLen - localStart)
            guard clampedLength > 0 else { continue }
            localPersistedRanges.append(NSRange(location: localStart, length: clampedLength))
        }

        // Active highlight (chunk-local)
        var activeLocal: NSRange? = nil
        if index == activeHighlightChunkIndex, let localRange = activeHighlightLocalRange {
            if localRange.location < chunkTextLen {
                let clampedLen = min(localRange.length, chunkTextLen - localRange.location)
                if clampedLen > 0 {
                    activeLocal = NSRange(location: localRange.location, length: clampedLen)
                }
            }
        }

        return (localPersistedRanges, activeLocal)
    }
}
#endif
