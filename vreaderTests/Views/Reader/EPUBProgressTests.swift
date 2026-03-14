// Purpose: Tests for EPUB reading progress calculation and seek logic (WI-004d).
// Validates progress computation from spine index + scroll fraction,
// seek-to-chapter mapping, discrete steps, label formatting, and edge cases.
//
// @coordinates-with: EPUBProgressCalculator.swift, EPUBReaderContainerView.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Progress Calculation

@Suite("EPUBProgressCalculator - Progress")
struct EPUBProgressCalculationTests {

    @Test("chapter 3 of 10 at 50% scroll gives progress ~0.25")
    func progressReflectsChapterAndScrollFraction() {
        // spineIndex=2 (0-based), scrollFraction=0.5, totalSpineItems=10
        // progress = (2 + 0.5) / 10 = 0.25
        let progress = EPUBProgressCalculator.progress(
            spineIndex: 2,
            scrollFraction: 0.5,
            totalSpineItems: 10
        )
        #expect(abs(progress - 0.25) < 0.001)
    }

    @Test("first chapter at top gives progress ~0.0")
    func progressZeroAtFirstChapter() {
        let progress = EPUBProgressCalculator.progress(
            spineIndex: 0,
            scrollFraction: 0.0,
            totalSpineItems: 10
        )
        #expect(abs(progress - 0.0) < 0.001)
    }

    @Test("last chapter at bottom gives progress 1.0")
    func progressOneAtLastChapter() {
        // spineIndex=9 (last of 10), scrollFraction=1.0
        // progress = (9 + 1.0) / 10 = 1.0
        let progress = EPUBProgressCalculator.progress(
            spineIndex: 9,
            scrollFraction: 1.0,
            totalSpineItems: 10
        )
        #expect(abs(progress - 1.0) < 0.001)
    }

    @Test("middle of second chapter in 3-chapter book")
    func progressMidSecondChapter() {
        // spineIndex=1, scrollFraction=0.5, totalSpineItems=3
        // progress = (1 + 0.5) / 3 = 0.5
        let progress = EPUBProgressCalculator.progress(
            spineIndex: 1,
            scrollFraction: 0.5,
            totalSpineItems: 3
        )
        #expect(abs(progress - 0.5) < 0.001)
    }

    @Test("single chapter EPUB at 50% scroll gives 0.5")
    func singleChapterProgress() {
        // 1 chapter: progress = scrollFraction directly
        let progress = EPUBProgressCalculator.progress(
            spineIndex: 0,
            scrollFraction: 0.5,
            totalSpineItems: 1
        )
        #expect(abs(progress - 0.5) < 0.001)
    }

    @Test("zero total spine items returns 0.0")
    func zeroSpineItemsReturnsZero() {
        let progress = EPUBProgressCalculator.progress(
            spineIndex: 0,
            scrollFraction: 0.5,
            totalSpineItems: 0
        )
        #expect(progress == 0.0)
    }

    @Test("negative spine index clamps to 0")
    func negativeSpineIndex() {
        let progress = EPUBProgressCalculator.progress(
            spineIndex: -1,
            scrollFraction: 0.5,
            totalSpineItems: 10
        )
        #expect(progress >= 0.0)
        #expect(progress <= 1.0)
    }

    @Test("scroll fraction > 1 clamps")
    func scrollFractionOverOne() {
        let progress = EPUBProgressCalculator.progress(
            spineIndex: 0,
            scrollFraction: 1.5,
            totalSpineItems: 10
        )
        #expect(progress <= 1.0)
    }

    @Test("scroll fraction < 0 clamps")
    func scrollFractionNegative() {
        let progress = EPUBProgressCalculator.progress(
            spineIndex: 0,
            scrollFraction: -0.5,
            totalSpineItems: 10
        )
        #expect(progress >= 0.0)
    }

    @Test("NaN scroll fraction produces safe output")
    func nanScrollFraction() {
        let progress = EPUBProgressCalculator.progress(
            spineIndex: 0,
            scrollFraction: .nan,
            totalSpineItems: 10
        )
        #expect(progress >= 0.0)
        #expect(progress <= 1.0)
        #expect(!progress.isNaN)
    }
}

// MARK: - Seek Target

@Suite("EPUBProgressCalculator - Seek")
struct EPUBProgressSeekTests {

    @Test("seeking to 0.5 with 10 chapters goes to chapter 5")
    func seekNavigatesToChapter() {
        let target = EPUBProgressCalculator.seekTarget(
            seekValue: 0.5,
            totalSpineItems: 10
        )
        #expect(target.spineIndex == 5)
        #expect(abs(target.scrollFraction - 0.0) < 0.001)
    }

    @Test("seeking to 0.0 goes to first chapter at top")
    func seekToZero() {
        let target = EPUBProgressCalculator.seekTarget(
            seekValue: 0.0,
            totalSpineItems: 10
        )
        #expect(target.spineIndex == 0)
        #expect(abs(target.scrollFraction - 0.0) < 0.001)
    }

    @Test("seeking to 1.0 goes to last chapter at bottom")
    func seekToOne() {
        let target = EPUBProgressCalculator.seekTarget(
            seekValue: 1.0,
            totalSpineItems: 10
        )
        #expect(target.spineIndex == 9)
        #expect(abs(target.scrollFraction - 1.0) < 0.001)
    }

    @Test("seeking to 0.25 with 10 chapters goes to chapter 2 at 50%")
    func seekToFractionalPosition() {
        // 0.25 * 10 = 2.5 → spineIndex=2, scrollFraction=0.5
        let target = EPUBProgressCalculator.seekTarget(
            seekValue: 0.25,
            totalSpineItems: 10
        )
        #expect(target.spineIndex == 2)
        #expect(abs(target.scrollFraction - 0.5) < 0.001)
    }

    @Test("seeking in single chapter returns spine 0 with scroll fraction")
    func seekSingleChapter() {
        let target = EPUBProgressCalculator.seekTarget(
            seekValue: 0.7,
            totalSpineItems: 1
        )
        #expect(target.spineIndex == 0)
        #expect(abs(target.scrollFraction - 0.7) < 0.001)
    }

    @Test("seeking with zero spine items returns safe default")
    func seekZeroSpineItems() {
        let target = EPUBProgressCalculator.seekTarget(
            seekValue: 0.5,
            totalSpineItems: 0
        )
        #expect(target.spineIndex == 0)
        #expect(target.scrollFraction >= 0.0)
    }

    @Test("seeking beyond 1.0 clamps to last chapter")
    func seekBeyondOne() {
        let target = EPUBProgressCalculator.seekTarget(
            seekValue: 1.5,
            totalSpineItems: 10
        )
        #expect(target.spineIndex == 9)
        #expect(target.scrollFraction <= 1.0)
    }

    @Test("seeking negative clamps to first chapter")
    func seekNegative() {
        let target = EPUBProgressCalculator.seekTarget(
            seekValue: -0.5,
            totalSpineItems: 10
        )
        #expect(target.spineIndex == 0)
        #expect(target.scrollFraction >= 0.0)
    }

    @Test("seeking NaN returns safe default")
    func seekNaN() {
        let target = EPUBProgressCalculator.seekTarget(
            seekValue: .nan,
            totalSpineItems: 10
        )
        #expect(target.spineIndex >= 0)
        #expect(!target.scrollFraction.isNaN)
    }
}

// MARK: - Discrete Steps

@Suite("EPUBProgressCalculator - Discrete Steps")
struct EPUBProgressDiscreteStepsTests {

    @Test("discrete steps equals spine item count for multi-chapter")
    func discreteStepsMatchChapterCount() {
        let steps = EPUBProgressCalculator.discreteSteps(totalSpineItems: 10)
        #expect(steps == 10)
    }

    @Test("single chapter EPUB has nil discrete steps (continuous)")
    func singleChapterEPUBProgressIsContinuous() {
        let steps = EPUBProgressCalculator.discreteSteps(totalSpineItems: 1)
        #expect(steps == nil)
    }

    @Test("zero spine items has nil discrete steps")
    func zeroSpineItemsNilSteps() {
        let steps = EPUBProgressCalculator.discreteSteps(totalSpineItems: 0)
        #expect(steps == nil)
    }

    @Test("two chapters gives 2 discrete steps")
    func twoChapters() {
        let steps = EPUBProgressCalculator.discreteSteps(totalSpineItems: 2)
        #expect(steps == 2)
    }
}

// MARK: - Label

@Suite("EPUBProgressCalculator - Label")
struct EPUBProgressLabelTests {

    @Test("label shows 'Chapter X of Y' format")
    func labelShowsChapterInfo() {
        let label = EPUBProgressCalculator.label(
            spineIndex: 2,
            totalSpineItems: 10
        )
        #expect(label == "Chapter 3 of 10")
    }

    @Test("label for first chapter")
    func labelFirstChapter() {
        let label = EPUBProgressCalculator.label(
            spineIndex: 0,
            totalSpineItems: 5
        )
        #expect(label == "Chapter 1 of 5")
    }

    @Test("label for last chapter")
    func labelLastChapter() {
        let label = EPUBProgressCalculator.label(
            spineIndex: 9,
            totalSpineItems: 10
        )
        #expect(label == "Chapter 10 of 10")
    }

    @Test("label for single chapter")
    func labelSingleChapter() {
        let label = EPUBProgressCalculator.label(
            spineIndex: 0,
            totalSpineItems: 1
        )
        #expect(label == "Chapter 1 of 1")
    }

    @Test("label for zero spine items returns nil")
    func labelZeroSpineItems() {
        let label = EPUBProgressCalculator.label(
            spineIndex: 0,
            totalSpineItems: 0
        )
        #expect(label == nil)
    }
}

// MARK: - Round-Trip Consistency

@Suite("EPUBProgressCalculator - Round Trip")
struct EPUBProgressRoundTripTests {

    @Test("progress → seek → progress round-trips for chapter boundaries")
    func roundTripChapterBoundaries() {
        for totalItems in [3, 5, 10, 20] {
            for spineIndex in 0..<totalItems {
                let progress = EPUBProgressCalculator.progress(
                    spineIndex: spineIndex,
                    scrollFraction: 0.0,
                    totalSpineItems: totalItems
                )
                let target = EPUBProgressCalculator.seekTarget(
                    seekValue: progress,
                    totalSpineItems: totalItems
                )
                #expect(
                    target.spineIndex == spineIndex,
                    "Round trip failed: totalItems=\(totalItems), spineIndex=\(spineIndex), progress=\(progress), got spineIndex=\(target.spineIndex)"
                )
            }
        }
    }

    @Test("progress → seek round-trips for mid-chapter positions")
    func roundTripMidChapter() {
        let totalItems = 10
        let spineIndex = 4
        let scrollFraction = 0.6
        let progress = EPUBProgressCalculator.progress(
            spineIndex: spineIndex,
            scrollFraction: scrollFraction,
            totalSpineItems: totalItems
        )
        let target = EPUBProgressCalculator.seekTarget(
            seekValue: progress,
            totalSpineItems: totalItems
        )
        #expect(target.spineIndex == spineIndex)
        #expect(abs(target.scrollFraction - scrollFraction) < 0.001)
    }
}
