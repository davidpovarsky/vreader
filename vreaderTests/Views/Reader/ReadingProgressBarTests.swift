// Purpose: Tests for ReadingProgressBar shared component (WI-004a).
// Validates clamping, discrete step snapping, visibility, and onSeek callback.
//
// @coordinates-with ReadingProgressBar.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReadingProgressBar")
struct ReadingProgressBarTests {

    // MARK: - Defaults

    @Test func progressDefaultsToZero() {
        // ReadingProgressBar.clampedProgress should treat 0.0 correctly
        let clamped = ReadingProgressBar.clampedProgress(0.0)
        #expect(clamped == 0.0)
    }

    // MARK: - Clamping

    @Test func scrubberReflectsCurrentPosition() {
        let clamped = ReadingProgressBar.clampedProgress(0.5)
        #expect(clamped == 0.5)
    }

    @Test func scrubberClampsNegativeToZero() {
        let clamped = ReadingProgressBar.clampedProgress(-0.5)
        #expect(clamped == 0.0)
    }

    @Test func scrubberClampsAboveOneToOne() {
        let clamped = ReadingProgressBar.clampedProgress(1.5)
        #expect(clamped == 1.0)
    }

    @Test func scrubberClampsExactBoundaries() {
        #expect(ReadingProgressBar.clampedProgress(0.0) == 0.0)
        #expect(ReadingProgressBar.clampedProgress(1.0) == 1.0)
    }

    @Test func scrubberClampsNaN() {
        let clamped = ReadingProgressBar.clampedProgress(Double.nan)
        #expect(clamped == 0.0)
    }

    @Test func scrubberClampsInfinity() {
        #expect(ReadingProgressBar.clampedProgress(Double.infinity) == 1.0)
        #expect(ReadingProgressBar.clampedProgress(-Double.infinity) == 0.0)
    }

    // MARK: - Discrete Step Snapping

    @Test func discreteStepsSnapToNearest() {
        // 10 steps: 0.0, 0.1, 0.2, ..., 1.0
        // Seeking to 0.37 should snap to 0.4
        let snapped = ReadingProgressBar.snappedValue(0.37, discreteSteps: 10)
        #expect(snapped == 0.4)
    }

    @Test func discreteStepsSnapDownward() {
        // 10 steps: seeking to 0.34 snaps to 0.3
        let snapped = ReadingProgressBar.snappedValue(0.34, discreteSteps: 10)
        #expect(snapped == 0.3)
    }

    @Test func discreteStepsSnapExactStep() {
        // Already on a step boundary
        let snapped = ReadingProgressBar.snappedValue(0.5, discreteSteps: 10)
        #expect(snapped == 0.5)
    }

    @Test func discreteStepsSnapBoundaries() {
        let snapped0 = ReadingProgressBar.snappedValue(0.0, discreteSteps: 10)
        let snapped1 = ReadingProgressBar.snappedValue(1.0, discreteSteps: 10)
        #expect(snapped0 == 0.0)
        #expect(snapped1 == 1.0)
    }

    @Test func discreteStepsSingleStep() {
        // 1 step means only 0 and 1 — snap 0.3 to 0.0, snap 0.7 to 1.0
        let low = ReadingProgressBar.snappedValue(0.3, discreteSteps: 1)
        let high = ReadingProgressBar.snappedValue(0.7, discreteSteps: 1)
        #expect(low == 0.0)
        #expect(high == 1.0)
    }

    @Test func discreteStepsZeroFallsBackToContinuous() {
        // 0 steps is invalid — should pass through raw value
        let result = ReadingProgressBar.snappedValue(0.37, discreteSteps: 0)
        #expect(result == 0.37)
    }

    @Test func discreteStepsNegativeFallsBackToContinuous() {
        // Negative steps is invalid — should pass through raw value
        let result = ReadingProgressBar.snappedValue(0.37, discreteSteps: -5)
        #expect(result == 0.37)
    }

    // MARK: - Continuous Seek

    @Test func continuousSeekPassesThroughExactValue() {
        // nil discreteSteps → raw value
        let result = ReadingProgressBar.snappedValue(0.37, discreteSteps: nil)
        #expect(result == 0.37)
    }

    @Test func continuousSeekPassesThroughSmallValue() {
        let result = ReadingProgressBar.snappedValue(0.001, discreteSteps: nil)
        #expect(result == 0.001)
    }

    // MARK: - resolveSeekValue (combined clamp + snap)

    @Test func resolveSeekValueClampsAndSnaps() {
        // Out-of-range value with discrete steps
        let result = ReadingProgressBar.resolveSeekValue(1.7, discreteSteps: 10)
        #expect(result == 1.0) // clamp to 1.0, then snap to 1.0
    }

    @Test func resolveSeekValueContinuousClamp() {
        let result = ReadingProgressBar.resolveSeekValue(-0.3, discreteSteps: nil)
        #expect(result == 0.0)
    }

    // MARK: - Label Formatting

    @Test func labelFormatsPercentage() {
        let label = ReadingProgressBar.formatLabel(progress: 0.42, label: nil)
        #expect(label == "42%")
    }

    @Test func labelFormatsCustomLabel() {
        let label = ReadingProgressBar.formatLabel(progress: 0.5, label: "Page 3 of 10")
        #expect(label == "Page 3 of 10")
    }

    @Test func labelFormatsZeroPercent() {
        let label = ReadingProgressBar.formatLabel(progress: 0.0, label: nil)
        #expect(label == "0%")
    }

    @Test func labelFormatsHundredPercent() {
        let label = ReadingProgressBar.formatLabel(progress: 1.0, label: nil)
        #expect(label == "100%")
    }
}
