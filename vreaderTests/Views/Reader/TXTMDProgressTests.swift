// Purpose: Tests for reading progress bar wiring in TXT and MD readers (WI-004b).
// Validates progress computation from scroll position, seek-to-offset conversion,
// boundary conditions, empty content handling, and visibility rules.
//
// @coordinates-with: ScrollProgressHelper.swift, TXTReaderContainerView.swift,
//   MDReaderContainerView.swift, ReadingProgressBar.swift

import Testing
import Foundation
@testable import vreader

@Suite("TXT/MD Reading Progress")
struct TXTMDProgressTests {

    // MARK: - Progress from Scroll Position

    @Test func progressReflectsScrollPosition() {
        // Scrolling to 50% of content → progress 0.5
        let progress = ScrollProgressHelper.progress(
            contentOffset: 500,
            contentHeight: 1100,
            frameHeight: 100
        )
        #expect(progress == 0.5)
    }

    @Test func progressZeroAtTop() {
        // At start of document → progress 0.0
        let progress = ScrollProgressHelper.progress(
            contentOffset: 0,
            contentHeight: 2000,
            frameHeight: 500
        )
        #expect(progress == 0.0)
    }

    @Test func progressOneAtBottom() {
        // At end of document → progress 1.0
        // contentOffset at max = contentHeight - frameHeight
        let contentHeight: CGFloat = 2000
        let frameHeight: CGFloat = 500
        let maxOffset = contentHeight - frameHeight
        let progress = ScrollProgressHelper.progress(
            contentOffset: maxOffset,
            contentHeight: contentHeight,
            frameHeight: frameHeight
        )
        #expect(progress == 1.0)
    }

    @Test func progressClampsNegativeOffset() {
        // Negative offset (rubber-band scroll) → 0.0
        let progress = ScrollProgressHelper.progress(
            contentOffset: -50,
            contentHeight: 2000,
            frameHeight: 500
        )
        #expect(progress == 0.0)
    }

    @Test func progressClampsBeyondBottom() {
        // Offset beyond max (rubber-band overscroll) → 1.0
        let progress = ScrollProgressHelper.progress(
            contentOffset: 2000,
            contentHeight: 2000,
            frameHeight: 500
        )
        #expect(progress == 1.0)
    }

    // MARK: - Seek to Offset

    @Test func seekScrollsToCorrectOffset() {
        // Seeking to 0.75 → scrolls to 75% of scrollable range
        let offset = ScrollProgressHelper.seekOffset(
            progress: 0.75,
            contentHeight: 2000,
            frameHeight: 500
        )
        // scrollable range = 2000 - 500 = 1500; 0.75 * 1500 = 1125
        #expect(offset == 1125.0)
    }

    @Test func seekToZeroReturnsZero() {
        let offset = ScrollProgressHelper.seekOffset(
            progress: 0.0,
            contentHeight: 2000,
            frameHeight: 500
        )
        #expect(offset == 0.0)
    }

    @Test func seekToOneReturnsMaxOffset() {
        let offset = ScrollProgressHelper.seekOffset(
            progress: 1.0,
            contentHeight: 2000,
            frameHeight: 500
        )
        // scrollable range = 1500
        #expect(offset == 1500.0)
    }

    @Test func seekClampsNegativeProgress() {
        let offset = ScrollProgressHelper.seekOffset(
            progress: -0.5,
            contentHeight: 2000,
            frameHeight: 500
        )
        #expect(offset == 0.0)
    }

    @Test func seekClampsBeyondOneProgress() {
        let offset = ScrollProgressHelper.seekOffset(
            progress: 1.5,
            contentHeight: 2000,
            frameHeight: 500
        )
        // Should clamp to max scrollable offset
        #expect(offset == 1500.0)
    }

    // MARK: - Round Trip

    @Test func seekRoundTrips() {
        // seek to X → read position → matches X (within tolerance)
        let targetProgress = 0.42
        let contentHeight: CGFloat = 3000
        let frameHeight: CGFloat = 600

        let seekY = ScrollProgressHelper.seekOffset(
            progress: targetProgress,
            contentHeight: contentHeight,
            frameHeight: frameHeight
        )
        let readBack = ScrollProgressHelper.progress(
            contentOffset: seekY,
            contentHeight: contentHeight,
            frameHeight: frameHeight
        )
        // Should match within floating-point tolerance
        #expect(abs(readBack - targetProgress) < 0.0001)
    }

    @Test func seekRoundTripsBoundaryZero() {
        let seekY = ScrollProgressHelper.seekOffset(
            progress: 0.0, contentHeight: 1000, frameHeight: 200
        )
        let readBack = ScrollProgressHelper.progress(
            contentOffset: seekY, contentHeight: 1000, frameHeight: 200
        )
        #expect(readBack == 0.0)
    }

    @Test func seekRoundTripsBoundaryOne() {
        let seekY = ScrollProgressHelper.seekOffset(
            progress: 1.0, contentHeight: 1000, frameHeight: 200
        )
        let readBack = ScrollProgressHelper.progress(
            contentOffset: seekY, contentHeight: 1000, frameHeight: 200
        )
        #expect(readBack == 1.0)
    }

    // MARK: - Empty/Short Content

    @Test func emptyContentProgressIsZero() {
        // No content → progress stays 0
        let progress = ScrollProgressHelper.progress(
            contentOffset: 0,
            contentHeight: 0,
            frameHeight: 500
        )
        #expect(progress == 0.0)
    }

    @Test func contentSmallerThanFrameProgressIsZero() {
        // Content fits in frame → progress 0
        let progress = ScrollProgressHelper.progress(
            contentOffset: 0,
            contentHeight: 300,
            frameHeight: 500
        )
        #expect(progress == 0.0)
    }

    @Test func contentEqualToFrameProgressIsZero() {
        // Content exactly equals frame → no scrollable area → progress 0
        let progress = ScrollProgressHelper.progress(
            contentOffset: 0,
            contentHeight: 500,
            frameHeight: 500
        )
        #expect(progress == 0.0)
    }

    @Test func seekWithNoScrollableRangeReturnsZero() {
        // Content fits in frame → seek returns 0
        let offset = ScrollProgressHelper.seekOffset(
            progress: 0.5,
            contentHeight: 300,
            frameHeight: 500
        )
        #expect(offset == 0.0)
    }

    // MARK: - Visibility

    @Test func progressBarHiddenWhenNoContent() {
        // Empty document → isVisible false
        let visible = ScrollProgressHelper.shouldShowProgressBar(
            hasContent: false,
            contentHeight: 0,
            frameHeight: 500
        )
        #expect(visible == false)
    }

    @Test func progressBarHiddenWhenContentFitsFrame() {
        // Very short document (content < frame) → isVisible false
        let visible = ScrollProgressHelper.shouldShowProgressBar(
            hasContent: true,
            contentHeight: 300,
            frameHeight: 500
        )
        #expect(visible == false)
    }

    @Test func progressBarVisibleWhenContentExceedsFrame() {
        let visible = ScrollProgressHelper.shouldShowProgressBar(
            hasContent: true,
            contentHeight: 2000,
            frameHeight: 500
        )
        #expect(visible == true)
    }

    @Test func progressBarHiddenWhenContentEqualsFrame() {
        // Edge case: content exactly equals frame height → nothing to scroll
        let visible = ScrollProgressHelper.shouldShowProgressBar(
            hasContent: true,
            contentHeight: 500,
            frameHeight: 500
        )
        #expect(visible == false)
    }

    @Test func progressBarHiddenWhenZeroFrameHeight() {
        // Edge case: frame not yet laid out
        let visible = ScrollProgressHelper.shouldShowProgressBar(
            hasContent: true,
            contentHeight: 2000,
            frameHeight: 0
        )
        #expect(visible == false)
    }

    // MARK: - Char Offset from Progress

    @Test func charOffsetFromProgressAtMiddle() {
        let offset = ScrollProgressHelper.charOffsetFromProgress(
            progress: 0.5,
            totalLengthUTF16: 1000
        )
        #expect(offset == 500)
    }

    @Test func charOffsetFromProgressAtStart() {
        let offset = ScrollProgressHelper.charOffsetFromProgress(
            progress: 0.0,
            totalLengthUTF16: 1000
        )
        #expect(offset == 0)
    }

    @Test func charOffsetFromProgressAtEnd() {
        let offset = ScrollProgressHelper.charOffsetFromProgress(
            progress: 1.0,
            totalLengthUTF16: 1000
        )
        #expect(offset == 1000)
    }

    @Test func charOffsetFromProgressClampsNegative() {
        let offset = ScrollProgressHelper.charOffsetFromProgress(
            progress: -0.5,
            totalLengthUTF16: 1000
        )
        #expect(offset == 0)
    }

    @Test func charOffsetFromProgressClampsBeyondOne() {
        let offset = ScrollProgressHelper.charOffsetFromProgress(
            progress: 1.5,
            totalLengthUTF16: 1000
        )
        #expect(offset == 1000)
    }

    @Test func charOffsetFromProgressWithZeroLength() {
        let offset = ScrollProgressHelper.charOffsetFromProgress(
            progress: 0.5,
            totalLengthUTF16: 0
        )
        #expect(offset == 0)
    }

    // MARK: - Label Formatting

    @Test func percentageLabelFormatting() {
        #expect(ScrollProgressHelper.percentageLabel(0.0) == "0%")
        #expect(ScrollProgressHelper.percentageLabel(0.456) == "45%")
        #expect(ScrollProgressHelper.percentageLabel(1.0) == "100%")
    }

    @Test func percentageLabelClampsOutOfRange() {
        #expect(ScrollProgressHelper.percentageLabel(-0.5) == "0%")
        #expect(ScrollProgressHelper.percentageLabel(1.5) == "100%")
    }
}
