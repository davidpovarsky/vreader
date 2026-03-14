// Purpose: Pure-logic helpers for EPUB reading progress bar wiring (WI-004d).
// Converts between spine indices + scroll fractions and progress values (0.0-1.0),
// generates chapter labels, and determines discrete step mode.
//
// Key decisions:
// - All methods are static for testability (no ViewModel coupling).
// - Progress formula: (spineIndex + scrollFraction) / totalSpineItems.
// - Single-chapter EPUBs use continuous scroll (nil discreteSteps).
// - Multi-chapter EPUBs snap to chapter boundaries (discreteSteps = spineCount).
// - Seek targets decompose a 0.0-1.0 value back into (spineIndex, scrollFraction).
// - All inputs are clamped to safe ranges (NaN, negative, overflow).
//
// @coordinates-with: ReadingProgressBar.swift, EPUBReaderContainerView.swift

import Foundation

/// Pure-logic helpers for wiring ReadingProgressBar into the EPUB reader.
enum EPUBProgressCalculator {

    /// Result of a seek operation: which spine item to navigate to and where within it.
    struct SeekTarget {
        let spineIndex: Int
        let scrollFraction: Double
    }

    // MARK: - Progress Computation

    /// Computes overall reading progress (0.0-1.0) from spine position and scroll fraction.
    ///
    /// Formula: `(spineIndex + scrollFraction) / totalSpineItems`
    ///
    /// - Parameters:
    ///   - spineIndex: Zero-based index of the current spine item.
    ///   - scrollFraction: Scroll position within the current spine item (0.0-1.0).
    ///   - totalSpineItems: Total number of spine items in the EPUB.
    /// - Returns: Overall progress clamped to 0.0-1.0.
    static func progress(
        spineIndex: Int,
        scrollFraction: Double,
        totalSpineItems: Int
    ) -> Double {
        guard totalSpineItems > 0 else { return 0.0 }
        let safeIndex = max(0, spineIndex)
        let safeFraction = clamp(scrollFraction)
        let raw = (Double(safeIndex) + safeFraction) / Double(totalSpineItems)
        return min(max(raw, 0.0), 1.0)
    }

    // MARK: - Seek Target

    /// Decomposes a seek value (0.0-1.0) into a spine index and scroll fraction.
    ///
    /// Inverse of `progress()`: `seekValue * totalSpineItems` gives the continuous position,
    /// which is split into integer (spine index) and fractional (scroll position) parts.
    ///
    /// - Parameters:
    ///   - seekValue: The progress bar value (0.0-1.0).
    ///   - totalSpineItems: Total number of spine items in the EPUB.
    /// - Returns: A `SeekTarget` with the spine index and scroll fraction.
    static func seekTarget(
        seekValue: Double,
        totalSpineItems: Int
    ) -> SeekTarget {
        guard totalSpineItems > 0 else {
            return SeekTarget(spineIndex: 0, scrollFraction: 0.0)
        }
        let clamped = clamp(seekValue)
        let continuous = clamped * Double(totalSpineItems)
        var spineIndex = Int(continuous)
        var scrollFraction = continuous - Double(spineIndex)

        // Clamp spine index to valid range
        if spineIndex >= totalSpineItems {
            spineIndex = totalSpineItems - 1
            scrollFraction = 1.0
        }

        return SeekTarget(
            spineIndex: spineIndex,
            scrollFraction: min(max(scrollFraction, 0.0), 1.0)
        )
    }

    // MARK: - Discrete Steps

    /// Returns the number of discrete steps for the progress bar slider.
    /// Multi-chapter EPUBs snap to chapter boundaries; single or zero-chapter EPUBs
    /// use continuous mode (nil).
    static func discreteSteps(totalSpineItems: Int) -> Int? {
        guard totalSpineItems > 1 else { return nil }
        return totalSpineItems
    }

    // MARK: - Label

    /// Formats a "Chapter X of Y" label from a zero-based spine index.
    /// Returns nil for empty EPUBs (zero spine items).
    static func label(spineIndex: Int, totalSpineItems: Int) -> String? {
        guard totalSpineItems > 0 else { return nil }
        return "Chapter \(spineIndex + 1) of \(totalSpineItems)"
    }

    // MARK: - Private Helpers

    /// Clamps a double to 0.0-1.0, treating NaN as 0.0.
    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return min(max(value, 0.0), 1.0)
    }
}
