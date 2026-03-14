// Purpose: Tests for PDF reading progress bar wiring (WI-004c).
// Validates progress computation, seek-to-page conversion, label formatting,
// discrete step mapping, and edge cases (single page, empty, boundaries).
//
// @coordinates-with: PDFReaderContainerView.swift, ReadingProgressBar.swift

import Testing
import Foundation
@testable import vreader

@Suite("PDFProgress")
struct PDFProgressTests {

    // MARK: - Progress Reflects Current Page

    @Test("page 5 of 10 produces correct progress")
    func progressReflectsCurrentPage() {
        // Page index 4 (0-based) of 10 pages => 4 / 9 ≈ 0.444
        let progress = PDFProgressHelper.progressForPage(
            currentPageIndex: 4, totalPages: 10
        )
        let expected = 4.0 / 9.0
        #expect(abs(progress - expected) < 0.001)
    }

    @Test("page index 5 (0-based) of 10 pages")
    func progressAtPageIndexFive() {
        let progress = PDFProgressHelper.progressForPage(
            currentPageIndex: 5, totalPages: 10
        )
        let expected = 5.0 / 9.0
        #expect(abs(progress - expected) < 0.001)
    }

    // MARK: - Seek Navigates to Page

    @Test("seeking to 0.7 with 10 pages goes to correct page")
    func seekNavigatesToPage() {
        // 0.7 * 9 = 6.3, rounded = 6
        let page = PDFProgressHelper.pageForSeekValue(
            seekValue: 0.7, totalPages: 10
        )
        #expect(page == 6)
    }

    @Test("seeking to 0.0 goes to first page")
    func seekToZeroGoesToFirstPage() {
        let page = PDFProgressHelper.pageForSeekValue(
            seekValue: 0.0, totalPages: 10
        )
        #expect(page == 0)
    }

    @Test("seeking to 1.0 goes to last page")
    func seekToOneGoesToLastPage() {
        let page = PDFProgressHelper.pageForSeekValue(
            seekValue: 1.0, totalPages: 10
        )
        #expect(page == 9)
    }

    @Test("seeking to 0.5 with 10 pages")
    func seekToHalf() {
        // 0.5 * 9 = 4.5, rounded = 5 (but could be 4 depending on rounding)
        let page = PDFProgressHelper.pageForSeekValue(
            seekValue: 0.5, totalPages: 10
        )
        // (0.5 * 9).rounded() = 5.0 -> Int = 5
        #expect(page == 5)
    }

    // MARK: - Discrete Steps Match Page Intervals

    @Test("discrete steps is totalPages-1 so snapping aligns with page boundaries")
    func discreteStepsMatchPageIntervals() {
        // 10 pages → progress at k/9 for k=0..9 → 9 intervals → discreteSteps = 9
        let steps = PDFProgressHelper.discreteSteps(totalPages: 10)
        #expect(steps == 9)
    }

    @Test("discrete steps for two pages is 1")
    func discreteStepsTwoPages() {
        // 2 pages → progress 0.0 and 1.0 → 1 interval → discreteSteps = 1
        let steps = PDFProgressHelper.discreteSteps(totalPages: 2)
        #expect(steps == 1)
    }

    @Test("discrete steps for single page returns nil")
    func discreteStepsSinglePage() {
        // 1 page → always progress 1.0, no snapping needed
        let steps = PDFProgressHelper.discreteSteps(totalPages: 1)
        #expect(steps == nil)
    }

    @Test("discrete steps for zero pages returns nil")
    func discreteStepsZeroPages() {
        let steps = PDFProgressHelper.discreteSteps(totalPages: 0)
        #expect(steps == nil)
    }

    // MARK: - Progress Zero at First Page

    @Test("progress is 0.0 at first page")
    func progressZeroAtFirstPage() {
        let progress = PDFProgressHelper.progressForPage(
            currentPageIndex: 0, totalPages: 10
        )
        #expect(progress == 0.0)
    }

    // MARK: - Progress One at Last Page

    @Test("progress is 1.0 at last page")
    func progressOneAtLastPage() {
        let progress = PDFProgressHelper.progressForPage(
            currentPageIndex: 9, totalPages: 10
        )
        #expect(progress == 1.0)
    }

    // MARK: - Single Page Document

    @Test("single page document progress is 1.0")
    func singlePageDocProgressIsOne() {
        let progress = PDFProgressHelper.progressForPage(
            currentPageIndex: 0, totalPages: 1
        )
        #expect(progress == 1.0)
    }

    // MARK: - Label Shows Page Info

    @Test("label format is Page X of Y")
    func labelShowsPageInfo() {
        let label = PDFProgressHelper.pageLabel(
            currentPageIndex: 4, totalPages: 10
        )
        #expect(label == "Page 5 of 10")
    }

    @Test("label at first page")
    func labelAtFirstPage() {
        let label = PDFProgressHelper.pageLabel(
            currentPageIndex: 0, totalPages: 10
        )
        #expect(label == "Page 1 of 10")
    }

    @Test("label at last page")
    func labelAtLastPage() {
        let label = PDFProgressHelper.pageLabel(
            currentPageIndex: 9, totalPages: 10
        )
        #expect(label == "Page 10 of 10")
    }

    @Test("label for single page document")
    func labelSinglePage() {
        let label = PDFProgressHelper.pageLabel(
            currentPageIndex: 0, totalPages: 1
        )
        #expect(label == "Page 1 of 1")
    }

    // MARK: - Edge Cases

    @Test("progress for zero pages returns 0.0")
    func progressZeroPages() {
        let progress = PDFProgressHelper.progressForPage(
            currentPageIndex: 0, totalPages: 0
        )
        #expect(progress == 0.0)
    }

    @Test("seek with zero pages returns 0")
    func seekZeroPages() {
        let page = PDFProgressHelper.pageForSeekValue(
            seekValue: 0.5, totalPages: 0
        )
        #expect(page == 0)
    }

    @Test("seek with single page returns 0")
    func seekSinglePage() {
        let page = PDFProgressHelper.pageForSeekValue(
            seekValue: 0.5, totalPages: 1
        )
        #expect(page == 0)
    }

    @Test("label for zero pages")
    func labelZeroPages() {
        let label = PDFProgressHelper.pageLabel(
            currentPageIndex: 0, totalPages: 0
        )
        #expect(label == "Page 0 of 0")
    }

    @Test("very large PDF (1000 pages) discrete steps")
    func largePDFDiscreteSteps() {
        let steps = PDFProgressHelper.discreteSteps(totalPages: 1000)
        #expect(steps == 999)
    }

    @Test("very large PDF seek to middle")
    func largePDFSeekToMiddle() {
        let page = PDFProgressHelper.pageForSeekValue(
            seekValue: 0.5, totalPages: 1000
        )
        // 0.5 * 999 = 499.5, rounded = 500
        #expect(page == 500)
    }

    @Test("progress round-trip: progress -> seek -> same page")
    func progressRoundTrip() {
        let totalPages = 20
        for pageIndex in 0..<totalPages {
            let progress = PDFProgressHelper.progressForPage(
                currentPageIndex: pageIndex, totalPages: totalPages
            )
            let recoveredPage = PDFProgressHelper.pageForSeekValue(
                seekValue: progress, totalPages: totalPages
            )
            #expect(
                recoveredPage == pageIndex,
                "Round-trip failed for page \(pageIndex): progress=\(progress), recovered=\(recoveredPage)"
            )
        }
    }

    @Test("snapping via ReadingProgressBar aligns with page boundaries")
    func snappingAlignsWithPageBoundaries() {
        let totalPages = 10
        let steps = PDFProgressHelper.discreteSteps(totalPages: totalPages)
        // Every page progress value should survive snapping unchanged
        for pageIndex in 0..<totalPages {
            let progress = PDFProgressHelper.progressForPage(
                currentPageIndex: pageIndex, totalPages: totalPages
            )
            let snapped = ReadingProgressBar.snappedValue(progress, discreteSteps: steps)
            #expect(
                abs(snapped - progress) < 0.001,
                "Snap mismatch for page \(pageIndex): progress=\(progress), snapped=\(snapped)"
            )
        }
    }

    @Test("snapping produces exactly totalPages distinct positions")
    func snappingProducesCorrectPositionCount() {
        let totalPages = 10
        let steps = PDFProgressHelper.discreteSteps(totalPages: totalPages)
        // Sweep 0.0 to 1.0 and collect unique snapped values
        var positions = Set<Double>()
        for i in 0...1000 {
            let v = Double(i) / 1000.0
            let snapped = ReadingProgressBar.snappedValue(v, discreteSteps: steps)
            // Round to avoid floating-point noise in the Set
            positions.insert((snapped * 10000).rounded() / 10000)
        }
        #expect(
            positions.count == totalPages,
            "Expected \(totalPages) snap positions, got \(positions.count): \(positions.sorted())"
        )
    }

    @Test("seek clamps negative value to 0")
    func seekClampsNegative() {
        let page = PDFProgressHelper.pageForSeekValue(
            seekValue: -0.5, totalPages: 10
        )
        #expect(page == 0)
    }

    @Test("seek clamps value above 1 to last page")
    func seekClampsAboveOne() {
        let page = PDFProgressHelper.pageForSeekValue(
            seekValue: 1.5, totalPages: 10
        )
        #expect(page == 9)
    }

    @Test("visibility: hidden when document not loaded")
    func progressBarHiddenWhenNotLoaded() {
        let isVisible = PDFProgressHelper.shouldShowProgressBar(
            isDocumentLoaded: false, totalPages: 0
        )
        #expect(isVisible == false)
    }

    @Test("visibility: hidden when zero pages")
    func progressBarHiddenWhenZeroPages() {
        let isVisible = PDFProgressHelper.shouldShowProgressBar(
            isDocumentLoaded: true, totalPages: 0
        )
        #expect(isVisible == false)
    }

    @Test("visibility: shown when document loaded with pages")
    func progressBarShownWhenLoaded() {
        let isVisible = PDFProgressHelper.shouldShowProgressBar(
            isDocumentLoaded: true, totalPages: 10
        )
        #expect(isVisible == true)
    }
}
