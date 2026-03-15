// Purpose: Pure-logic helpers for scroll-based reading progress bar wiring (WI-004b).
// Converts between scroll positions and progress values (0.0-1.0),
// generates labels, and determines visibility for TXT/MD readers.
//
// Key decisions:
// - All methods are static for testability (no ViewModel coupling).
// - Progress is computed as contentOffset / (contentHeight - frameHeight).
// - When content fits in frame (no scrollable area), progress is 0.0.
// - Seek values are clamped to 0.0-1.0 before offset computation.
// - charOffsetFromProgress converts progress to UTF-16 character offset for seek navigation.
// - Labels use percentage format ("45%").
//
// @coordinates-with: ReadingProgressBar.swift, TXTReaderContainerView.swift,
//   MDReaderContainerView.swift

import Foundation

/// Pure-logic helpers for wiring ReadingProgressBar into TXT/MD readers.
enum ScrollProgressHelper {

    /// Computes reading progress (0.0-1.0) from scroll position.
    /// Returns 0.0 when content fits in frame or content/frame is empty.
    static func progress(
        contentOffset: CGFloat,
        contentHeight: CGFloat,
        frameHeight: CGFloat
    ) -> Double {
        let scrollableRange = contentHeight - frameHeight
        guard scrollableRange > 0 else { return 0.0 }
        let clamped = min(max(contentOffset, 0), scrollableRange)
        return Double(clamped / scrollableRange)
    }

    /// Converts a seek value (0.0-1.0) to a content offset (Y coordinate).
    /// Returns 0.0 when content fits in frame.
    static func seekOffset(
        progress: Double,
        contentHeight: CGFloat,
        frameHeight: CGFloat
    ) -> CGFloat {
        let scrollableRange = contentHeight - frameHeight
        guard scrollableRange > 0 else { return 0 }
        let clamped = min(max(progress, 0.0), 1.0)
        return CGFloat(clamped) * scrollableRange
    }

    /// Converts a progress value (0.0-1.0) to a UTF-16 character offset.
    /// Clamps progress to 0.0-1.0 and rounds to nearest integer offset.
    static func charOffsetFromProgress(
        progress: Double,
        totalLengthUTF16: Int
    ) -> Int {
        guard totalLengthUTF16 > 0 else { return 0 }
        let clamped = min(max(progress, 0.0), 1.0)
        let rawOffset = clamped * Double(totalLengthUTF16)
        return min(Int(rawOffset.rounded()), totalLengthUTF16)
    }

    /// Whether the progress bar should be visible.
    /// Hidden when no content, content fits in frame, or frame not laid out.
    static func shouldShowProgressBar(
        hasContent: Bool,
        contentHeight: CGFloat,
        frameHeight: CGFloat
    ) -> Bool {
        guard hasContent, frameHeight > 0 else { return false }
        return contentHeight > frameHeight
    }

    /// Formats a progress value as a percentage label (e.g. "45%").
    /// Clamps to 0-100%.
    static func percentageLabel(_ progress: Double) -> String {
        let clamped = min(max(progress, 0.0), 1.0)
        return "\(Int(clamped * 100))%"
    }
}
