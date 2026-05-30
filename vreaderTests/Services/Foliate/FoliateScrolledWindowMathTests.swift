// Purpose: Tests for FoliateScrolledWindowMath — the pure windowing math for
// the Feature #73 Foliate scrolled continuous surface. Covers window
// computation (clamping at both ends, K>total, K=1, empty), offset/section
// mapping (boundaries, out-of-range, empty), the Gate-2 C1 intra-section
// fraction contract, and evict adjustment.

import Testing
import Foundation
@testable import vreader

@Suite("FoliateScrolledWindowMath")
struct FoliateScrolledWindowMathTests {

    // MARK: - window

    @Test("window centers on current with K=3 in the middle")
    func windowMiddle() {
        #expect(FoliateScrolledWindowMath.window(current: 4, total: 10, k: 3) == 3...5)
    }

    @Test("window clamps + shifts inward at the start, preserving size")
    func windowAtStart() {
        #expect(FoliateScrolledWindowMath.window(current: 0, total: 10, k: 3) == 0...2)
        #expect(FoliateScrolledWindowMath.window(current: 1, total: 10, k: 3) == 0...2)
    }

    @Test("window clamps + shifts inward at the end, preserving size")
    func windowAtEnd() {
        #expect(FoliateScrolledWindowMath.window(current: 9, total: 10, k: 3) == 7...9)
        #expect(FoliateScrolledWindowMath.window(current: 8, total: 10, k: 3) == 7...9)
    }

    @Test("window clamps size to total when K exceeds total")
    func windowKExceedsTotal() {
        #expect(FoliateScrolledWindowMath.window(current: 1, total: 2, k: 5) == 0...1)
        #expect(FoliateScrolledWindowMath.window(current: 0, total: 1, k: 3) == 0...0)
    }

    @Test("window K=1 is just current")
    func windowK1() {
        #expect(FoliateScrolledWindowMath.window(current: 5, total: 10, k: 1) == 5...5)
    }

    @Test("window nil for empty book or non-positive K")
    func windowDegenerate() {
        #expect(FoliateScrolledWindowMath.window(current: 0, total: 0, k: 3) == nil)
        #expect(FoliateScrolledWindowMath.window(current: 0, total: 5, k: 0) == nil)
    }

    @Test("window clamps an out-of-range current")
    func windowCurrentOutOfRange() {
        #expect(FoliateScrolledWindowMath.window(current: 99, total: 10, k: 3) == 7...9)
        #expect(FoliateScrolledWindowMath.window(current: -5, total: 10, k: 3) == 0...2)
    }

    // MARK: - offsetOfSection

    @Test("offsetOfSection sums the sizes before the index")
    func offsetOfSection() {
        let sizes = [100.0, 200.0, 300.0]
        #expect(FoliateScrolledWindowMath.offsetOfSection(0, mountedSizes: sizes) == 0)
        #expect(FoliateScrolledWindowMath.offsetOfSection(1, mountedSizes: sizes) == 100)
        #expect(FoliateScrolledWindowMath.offsetOfSection(2, mountedSizes: sizes) == 300)
        #expect(FoliateScrolledWindowMath.offsetOfSection(3, mountedSizes: sizes) == 600) // == total
    }

    @Test("offsetOfSection handles empty + clamps")
    func offsetOfSectionEdges() {
        #expect(FoliateScrolledWindowMath.offsetOfSection(0, mountedSizes: []) == 0)
        #expect(FoliateScrolledWindowMath.offsetOfSection(-1, mountedSizes: [10, 20]) == 0)
        #expect(FoliateScrolledWindowMath.offsetOfSection(99, mountedSizes: [10, 20]) == 30)
    }

    // MARK: - sectionAtOffset

    @Test("sectionAtOffset maps offsets to sections; boundary belongs to later")
    func sectionAtOffset() {
        let sizes = [100.0, 200.0, 300.0]
        #expect(FoliateScrolledWindowMath.sectionAtOffset(0, mountedSizes: sizes) == 0)
        #expect(FoliateScrolledWindowMath.sectionAtOffset(50, mountedSizes: sizes) == 0)
        #expect(FoliateScrolledWindowMath.sectionAtOffset(100, mountedSizes: sizes) == 1) // boundary → later
        #expect(FoliateScrolledWindowMath.sectionAtOffset(250, mountedSizes: sizes) == 1)
        #expect(FoliateScrolledWindowMath.sectionAtOffset(300, mountedSizes: sizes) == 2)
        #expect(FoliateScrolledWindowMath.sectionAtOffset(9999, mountedSizes: sizes) == 2) // beyond end → last
    }

    @Test("sectionAtOffset handles empty + negative")
    func sectionAtOffsetEdges() {
        #expect(FoliateScrolledWindowMath.sectionAtOffset(50, mountedSizes: []) == 0)
        #expect(FoliateScrolledWindowMath.sectionAtOffset(-10, mountedSizes: [100]) == 0)
    }

    // MARK: - intraSectionFraction (Gate-2 C1 contract)

    @Test("intraSectionFraction returns (index, intra) — NOT whole-book")
    func intraSectionFraction() {
        let sizes = [100.0, 200.0, 300.0]
        // start of section 1 → intra 0
        var r = FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: 100, mountedSizes: sizes)
        #expect(r.index == 1)
        #expect(abs(r.intra - 0) < 1e-9)
        // middle of section 1 (offset 200, section spans 100..300) → intra 0.5
        r = FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: 200, mountedSizes: sizes)
        #expect(r.index == 1)
        #expect(abs(r.intra - 0.5) < 1e-9)
        // near end of section 2 (offset 590, section spans 300..600) → intra ~0.9667
        r = FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: 590, mountedSizes: sizes)
        #expect(r.index == 2)
        #expect(abs(r.intra - (290.0 / 300.0)) < 1e-9)
    }

    @Test("intraSectionFraction clamps + handles zero-size + empty")
    func intraSectionFractionEdges() {
        #expect(FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: 50, mountedSizes: []).index == 0)
        #expect(FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: 50, mountedSizes: []).intra == 0)
        // zero-size section → intra 0, no NaN
        let r = FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: 0, mountedSizes: [0, 100])
        #expect(r.index == 0)
        #expect(r.intra == 0)
        // negative offset clamps to (0, 0)
        let n = FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: -10, mountedSizes: [100])
        #expect(n.index == 0)
        #expect(n.intra == 0)
    }

    // MARK: - offsetAdjustmentOnEvict

    @Test("offsetAdjustmentOnEvict sums evicted sizes, ignores negatives")
    func offsetAdjustmentOnEvict() {
        #expect(FoliateScrolledWindowMath.offsetAdjustmentOnEvict(evictedSizesAbove: [100, 200]) == 300)
        #expect(FoliateScrolledWindowMath.offsetAdjustmentOnEvict(evictedSizesAbove: []) == 0)
        #expect(FoliateScrolledWindowMath.offsetAdjustmentOnEvict(evictedSizesAbove: [100, -50]) == 100)
    }
}
