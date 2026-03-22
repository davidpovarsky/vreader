// Purpose: Sorted array of offset mapping entries with binary search for
// bidirectional offset conversion between source and display text.
//
// Key decisions:
// - Entries are sorted by sourceOffset for O(log n) lookup.
// - Each entry records a point where offsets diverge (insert/delete/replace).
// - Identity map (no entries) means offsets are unchanged.
// - compose() chains two maps for sequential transforms.
//
// @coordinates-with: TextTransform.swift, TextMapper.swift

import Foundation

/// A single point where source and display offsets diverge.
struct OffsetEntry: Sendable, Equatable {
    /// Offset in source text where this change starts.
    let sourceOffset: Int
    /// Offset in display text where this change starts.
    let displayOffset: Int
    /// Length consumed in source text (original).
    let sourceLength: Int
    /// Length produced in display text (replacement).
    let displayLength: Int
}

/// Bidirectional offset mapping between source and display text.
struct OffsetMap: Sendable, Equatable {
    /// Sorted array of offset entries (by sourceOffset).
    private(set) var entries: [OffsetEntry]

    /// Total length of source text in UTF-16 code units.
    let sourceLengthUTF16: Int
    /// Total length of display text in UTF-16 code units.
    let displayLengthUTF16: Int

    /// Identity map: no offset changes.
    static func identity(lengthUTF16: Int) -> OffsetMap {
        OffsetMap(entries: [], sourceLengthUTF16: lengthUTF16, displayLengthUTF16: lengthUTF16)
    }

    init(entries: [OffsetEntry], sourceLengthUTF16: Int, displayLengthUTF16: Int) {
        self.entries = entries.sorted { $0.sourceOffset < $1.sourceOffset }
        self.sourceLengthUTF16 = sourceLengthUTF16
        self.displayLengthUTF16 = displayLengthUTF16
    }

    // MARK: - Source to Display

    /// Convert a source offset to the corresponding display offset.
    func sourceToDisplay(_ sourceOffset: Int) -> Int {
        guard !entries.isEmpty else { return sourceOffset }

        // Binary search for the last entry with sourceOffset <= target
        var lo = 0
        var hi = entries.count - 1
        var bestIndex = -1

        while lo <= hi {
            let mid = (lo + hi) / 2
            if entries[mid].sourceOffset <= sourceOffset {
                bestIndex = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        if bestIndex < 0 {
            // Before any entry — offset unchanged
            return sourceOffset
        }

        let entry = entries[bestIndex]
        let entrySourceEnd = entry.sourceOffset + entry.sourceLength

        if sourceOffset < entrySourceEnd {
            // Inside the replaced region — clamp to start of display replacement
            let fraction: Int
            if entry.sourceLength > 0 && entry.displayLength > 0 {
                // Proportional mapping within the replacement
                let offsetInSource = sourceOffset - entry.sourceOffset
                fraction = offsetInSource * entry.displayLength / entry.sourceLength
            } else {
                fraction = 0
            }
            return entry.displayOffset + fraction
        }

        // After the entry — compute accumulated delta
        let delta = (entry.displayOffset + entry.displayLength) - (entry.sourceOffset + entry.sourceLength)
        return sourceOffset + delta
    }

    // MARK: - Display to Source

    /// Convert a display offset to the corresponding source offset.
    func displayToSource(_ displayOffset: Int) -> Int {
        guard !entries.isEmpty else { return displayOffset }

        // Binary search on displayOffset
        var lo = 0
        var hi = entries.count - 1
        var bestIndex = -1

        while lo <= hi {
            let mid = (lo + hi) / 2
            if entries[mid].displayOffset <= displayOffset {
                bestIndex = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        if bestIndex < 0 {
            return displayOffset
        }

        let entry = entries[bestIndex]
        let entryDisplayEnd = entry.displayOffset + entry.displayLength

        if displayOffset < entryDisplayEnd {
            // Inside the replaced region
            let fraction: Int
            if entry.displayLength > 0 && entry.sourceLength > 0 {
                let offsetInDisplay = displayOffset - entry.displayOffset
                fraction = offsetInDisplay * entry.sourceLength / entry.displayLength
            } else {
                fraction = 0
            }
            return entry.sourceOffset + fraction
        }

        // After the entry
        let delta = (entry.sourceOffset + entry.sourceLength) - (entry.displayOffset + entry.displayLength)
        return displayOffset + delta
    }

    // MARK: - Range Conversion

    /// Convert a source range to a display range.
    func sourceRangeToDisplay(start: Int, length: Int) -> (start: Int, length: Int) {
        let displayStart = sourceToDisplay(start)
        let displayEnd = sourceToDisplay(start + length)
        return (start: displayStart, length: displayEnd - displayStart)
    }

    /// Convert a display range to a source range.
    func displayRangeToSource(start: Int, length: Int) -> (start: Int, length: Int) {
        let sourceStart = displayToSource(start)
        let sourceEnd = displayToSource(start + length)
        return (start: sourceStart, length: sourceEnd - sourceStart)
    }

    // MARK: - Composition

    /// Compose this map with another (applied after this one).
    /// self maps source→intermediate, other maps intermediate→display.
    func compose(with other: OffsetMap) -> OffsetMap {
        // For composition, we remap each entry through the other map
        var composed: [OffsetEntry] = []

        // Include entries from self, remapped through other
        for entry in entries {
            let newDisplayOffset = other.sourceToDisplay(entry.displayOffset)
            let newDisplayEnd = other.sourceToDisplay(entry.displayOffset + entry.displayLength)
            composed.append(OffsetEntry(
                sourceOffset: entry.sourceOffset,
                displayOffset: newDisplayOffset,
                sourceLength: entry.sourceLength,
                displayLength: newDisplayEnd - newDisplayOffset
            ))
        }

        // Include entries from other that fall in untouched regions
        for entry in other.entries {
            let sourceInSelf = displayToSource(entry.sourceOffset)
            // Check if this region is already covered by a self entry
            let alreadyCovered = entries.contains { selfEntry in
                let selfDisplayEnd = selfEntry.displayOffset + selfEntry.displayLength
                return entry.sourceOffset >= selfEntry.displayOffset && entry.sourceOffset < selfDisplayEnd
            }
            if !alreadyCovered {
                composed.append(OffsetEntry(
                    sourceOffset: sourceInSelf,
                    displayOffset: entry.displayOffset,
                    sourceLength: entry.sourceLength,
                    displayLength: entry.displayLength
                ))
            }
        }

        return OffsetMap(
            entries: composed,
            sourceLengthUTF16: sourceLengthUTF16,
            displayLengthUTF16: other.displayLengthUTF16
        )
    }
}
