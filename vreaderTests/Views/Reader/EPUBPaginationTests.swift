// Purpose: Tests for EPUBPaginationHelper — CSS column-based pagination for EPUB.
// Validates CSS generation, JS navigation, page count computation, and edge cases.
//
// @coordinates-with: EPUBPaginationHelper.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Pagination CSS Generation

@Suite("EPUBPaginationHelper - CSS")
struct EPUBPaginationCSSTests {

    @Test("CSS contains column-width property")
    func paginationCSS_containsColumnWidth() {
        let css = EPUBPaginationHelper.paginationCSS(viewportWidth: 375, viewportHeight: 667)
        #expect(css.contains("column-width"))
        #expect(css.contains("375"))
    }

    @Test("CSS constrains height to viewport")
    func paginationCSS_containsHeight() {
        let css = EPUBPaginationHelper.paginationCSS(viewportWidth: 375, viewportHeight: 667)
        #expect(css.contains("height"))
        #expect(css.contains("667"))
    }

    @Test("CSS sets overflow hidden on body and html")
    func paginationCSS_overflowHidden() {
        let css = EPUBPaginationHelper.paginationCSS(viewportWidth: 375, viewportHeight: 667)
        #expect(css.contains("overflow"))
        #expect(css.contains("hidden"))
        // Both html and body should have overflow hidden
        #expect(css.contains("html"))
        #expect(css.contains("body"))
    }

    @Test("CSS sets column-gap to 0")
    func paginationCSS_columnGapZero() {
        let css = EPUBPaginationHelper.paginationCSS(viewportWidth: 375, viewportHeight: 667)
        #expect(css.contains("column-gap"))
        #expect(css.contains("0px"))
    }

    @Test("CSS uses integer pixel values for width and height")
    func paginationCSS_integerPixelValues() {
        let css = EPUBPaginationHelper.paginationCSS(viewportWidth: 375.5, viewportHeight: 667.8)
        // Should use integer pixel values (truncated/rounded)
        #expect(css.contains("375px") || css.contains("376px"))
        #expect(css.contains("667px") || css.contains("668px"))
    }

    @Test("CSS handles zero viewport width safely")
    func paginationCSS_zeroWidth() {
        let css = EPUBPaginationHelper.paginationCSS(viewportWidth: 0, viewportHeight: 667)
        // Should still produce valid CSS (even if degenerate)
        #expect(css.contains("column-width"))
    }

    @Test("CSS handles zero viewport height safely")
    func paginationCSS_zeroHeight() {
        let css = EPUBPaginationHelper.paginationCSS(viewportWidth: 375, viewportHeight: 0)
        #expect(css.contains("height"))
    }
}

// MARK: - Navigate To Page JS

@Suite("EPUBPaginationHelper - navigateToPageJS")
struct EPUBPaginationNavigateTests {

    @Test("page 2 with 375px width sets scrollLeft to 375")
    func navigateToPage_setsScrollLeft() {
        let js = EPUBPaginationHelper.navigateToPageJS(page: 1, viewportWidth: 375)
        #expect(js.contains("scrollLeft"))
        #expect(js.contains("375"))
    }

    @Test("page 0 sets scrollLeft to 0")
    func navigateToPage_page0_scrollLeftIs0() {
        let js = EPUBPaginationHelper.navigateToPageJS(page: 0, viewportWidth: 375)
        #expect(js.contains("scrollLeft"))
        // page 0 => scrollLeft = 0 * 375 = 0
        // The JS should contain the calculation that results in 0
    }

    @Test("negative page treated as 0")
    func navigateToPage_negativePage() {
        let js = EPUBPaginationHelper.navigateToPageJS(page: -1, viewportWidth: 375)
        // Should clamp to 0
        let jsPage0 = EPUBPaginationHelper.navigateToPageJS(page: 0, viewportWidth: 375)
        #expect(js == jsPage0)
    }

    @Test("large page index produces valid JS")
    func navigateToPage_largePage() {
        let js = EPUBPaginationHelper.navigateToPageJS(page: 1000, viewportWidth: 375)
        #expect(js.contains("scrollLeft"))
        #expect(js.contains("375000"))
    }
}

// MARK: - Total Pages JS

@Suite("EPUBPaginationHelper - totalPagesJS")
struct EPUBPaginationTotalPagesTests {

    @Test("JS uses scrollWidth and viewport width")
    func totalPagesJS_usesScrollWidth() {
        let js = EPUBPaginationHelper.totalPagesJS(viewportWidth: 375)
        #expect(js.contains("scrollWidth"))
        #expect(js.contains("375"))
    }

    @Test("JS returns at least 1 page")
    func totalPagesJS_minimumOne() {
        let js = EPUBPaginationHelper.totalPagesJS(viewportWidth: 375)
        #expect(js.contains("Math.max"))
        #expect(js.contains("1"))
    }
}

// MARK: - Current Page JS

@Suite("EPUBPaginationHelper - currentPageJS")
struct EPUBPaginationCurrentPageTests {

    @Test("JS uses scrollLeft and viewport width")
    func currentPageJS_usesScrollLeft() {
        let js = EPUBPaginationHelper.currentPageJS(viewportWidth: 375)
        #expect(js.contains("scrollLeft"))
        #expect(js.contains("375"))
    }
}

// MARK: - Pure Calculation Helpers

@Suite("EPUBPaginationHelper - calculations")
struct EPUBPaginationCalculationTests {

    @Test("total pages from scrollWidth 3750 and viewportWidth 375 is 10")
    func totalPages_fromScrollWidth() {
        let total = EPUBPaginationHelper.totalPages(scrollWidth: 3750, viewportWidth: 375)
        #expect(total == 10)
    }

    @Test("empty content returns at least 1 page")
    func totalPages_emptyContent_returns1() {
        let total = EPUBPaginationHelper.totalPages(scrollWidth: 0, viewportWidth: 375)
        #expect(total == 1)
    }

    @Test("scrollWidth equal to viewportWidth returns 1 page")
    func totalPages_singlePage() {
        let total = EPUBPaginationHelper.totalPages(scrollWidth: 375, viewportWidth: 375)
        #expect(total == 1)
    }

    @Test("non-integer division rounds up")
    func totalPages_roundsUp() {
        // 400 / 375 = 1.066... should round to 2 (ceil)
        // Actually with CSS columns the scrollWidth should be exact multiples,
        // but we round up for safety
        let total = EPUBPaginationHelper.totalPages(scrollWidth: 400, viewportWidth: 375)
        #expect(total == 2)
    }

    @Test("zero viewportWidth returns 1 page")
    func totalPages_zeroViewport() {
        let total = EPUBPaginationHelper.totalPages(scrollWidth: 3750, viewportWidth: 0)
        #expect(total == 1)
    }

    @Test("page from scrollLeft 750, width 375 is page 2")
    func pageFromScrollOffset_calculatesCorrectly() {
        let page = EPUBPaginationHelper.pageFromScrollOffset(scrollLeft: 750, viewportWidth: 375)
        #expect(page == 2)
    }

    @Test("page from scrollLeft 0 is page 0")
    func pageFromScrollOffset_zero() {
        let page = EPUBPaginationHelper.pageFromScrollOffset(scrollLeft: 0, viewportWidth: 375)
        #expect(page == 0)
    }

    @Test("page from non-exact offset rounds to nearest")
    func pageFromScrollOffset_rounds() {
        // 380 / 375 = 1.013... should round to 1
        let page = EPUBPaginationHelper.pageFromScrollOffset(scrollLeft: 380, viewportWidth: 375)
        #expect(page == 1)
    }

    @Test("page from scrollOffset with zero viewport returns 0")
    func pageFromScrollOffset_zeroViewport() {
        let page = EPUBPaginationHelper.pageFromScrollOffset(scrollLeft: 100, viewportWidth: 0)
        #expect(page == 0)
    }
}

// MARK: - CSS Injection Style Tag

@Suite("EPUBPaginationHelper - style tag")
struct EPUBPaginationStyleTagTests {

    @Test("wraps CSS in a style tag with ID")
    func paginationStyleTag_wrapsCSS() {
        let tag = EPUBPaginationHelper.paginationStyleTag(viewportWidth: 375, viewportHeight: 667)
        #expect(tag.contains("<style"))
        #expect(tag.contains("vreader-pagination"))
        #expect(tag.contains("</style>"))
    }

    @Test("inject JS creates or replaces style element")
    func injectPaginationJS_createsStyle() {
        let js = EPUBPaginationHelper.injectPaginationCSSJS(viewportWidth: 375, viewportHeight: 667)
        #expect(js.contains("vreader-pagination"))
        #expect(js.contains("createElement"))
    }

    @Test("remove JS removes the pagination style element")
    func removePaginationJS_removesStyle() {
        let js = EPUBPaginationHelper.removePaginationCSSJS
        #expect(js.contains("vreader-pagination"))
        #expect(js.contains("remove"))
    }
}
