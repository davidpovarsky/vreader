# TextKit 2 Reflow Engine Spike — Results

**Date:** 2026-03-16
**iOS Target:** 17.0+
**SDK:** iOS Simulator 26.2 (Xcode 26)
**Test Device:** iPhone 17 Pro Simulator (arm64)

## Summary

**Decision: USE TextKit 2** for paginated text rendering in VReader iOS.

TextKit 2 produces correct, deterministic pagination results across all tested
scenarios — plain text, CJK, mixed scripts, edge cases. The API is
straightforward and integrates cleanly with UIKit font/layout conventions.

## Test Results (14/14 passed)

| Test | Result | Time |
|------|--------|------|
| `paginate_singlePageText_returns1Page` | PASS | 0.001s |
| `paginate_multiPageText_returnsCorrectPageCount` | PASS | 0.008s |
| `paginate_emptyText_returns0Pages` | PASS | 0.001s |
| `paginate_cjkText_correctBoundaries` | PASS | 0.022s |
| `paginate_mixedCJKLatin_noOrphanedLines` | PASS | 0.008s |
| `paginate_deterministic_sameInputSameOutput` | PASS | 0.003s |
| `pageAtIndex_returnsCorrectTextRange` | PASS | 0.004s |
| `offsetToPage_returnsCorrectPageIndex` | PASS | 0.004s |
| `viewportChange_recalculatesPages` | PASS | 0.005s |
| `fontSizeChange_recalculatesPages` | PASS | 0.009s |
| `allPages_coverEntireText_noGapsNoDuplicates` | PASS | 0.002s |
| `paginate_singleCharacter_returns1Page` | PASS | 0.001s |
| `paginate_onlyNewlines_handledGracefully` | PASS | 0.005s |
| `paginate_veryNarrowViewport_doesNotCrash` | PASS | 0.001s |

**Full suite time:** 0.076 seconds

## Does Pagination Produce Correct Results?

**Yes.** Validated by the `allPages_coverEntireText_noGapsNoDuplicates` test:

- Page ranges are **contiguous** (no gaps between pages).
- Page ranges are **non-overlapping** (no duplicated text).
- First page starts at offset 0.
- Last page ends at the total text length.
- Concatenating all page texts reconstructs the original text exactly.

## Performance

| Text Size | Line Count | Pages | Time |
|-----------|------------|-------|------|
| ~48 chars | 1 line | 1 | 0.001s |
| ~24 KB | 500 lines | ~18 | 0.008s |
| ~10 KB CJK | 5000 chars | ~6 | 0.022s |
| ~10 KB mixed | 200 lines | ~7 | 0.008s |
| ~14 KB | 300 lines | ~10 | 0.004s |

### Notes on Performance
- TextKit 2 layout is fast: 500 lines paginate in 8ms on simulator.
- 5000 CJK characters take 22ms — CJK layout is ~2.7x slower than Latin,
  likely due to more complex line breaking and glyph shaping.
- These times include full TextKit 2 stack setup (NSTextContentStorage,
  NSTextLayoutManager, NSTextContainer, attributed string creation).
- Performance on physical device will differ (typically faster due to
  Metal-accelerated text rendering).

### Scaling Estimate
For a 1MB plain text file (~500K ASCII characters, ~20K lines):
- Extrapolating from 500 lines @ 8ms: ~320ms
- For CJK (higher density): ~400-600ms
- This is acceptable for an initial page calculation on open.
- Incremental re-pagination on viewport/font change would benefit from
  caching the TextKit 2 stack and only recalculating page boundaries.

## CJK Correctness

**No issues found.** Validated by two dedicated tests:

1. **`paginate_cjkText_correctBoundaries`**: 5000 CJK characters paginated
   correctly. Each page's `textRange` maps to valid NSString boundaries.
   Extracting the substring with the range matches the stored page text.

2. **`paginate_mixedCJKLatin_noOrphanedLines`**: 200 alternating English/Chinese
   lines paginated without orphaned lines or corrupted boundaries. Full text
   reconstruction verified.

TextKit 2 handles CJK line breaking natively via `NSTextLayoutManager`, which
respects Unicode line break rules (UAX #14). No custom line-break logic needed.

## API Assessment

### What Works Well
- `NSTextLayoutManager.enumerateTextLayoutFragments()` gives per-paragraph
  layout fragments with precise frame rects.
- `NSTextContentStorage` cleanly bridges `NSAttributedString` to TextKit 2.
- `NSTextRange` to `NSRange` conversion works via offset calculations.
- Deterministic output: same input always produces identical pagination.

### API Surface Used
```swift
NSTextContentStorage          // Text content bridge
NSTextLayoutManager           // Layout engine
NSTextContainer               // Viewport constraints
NSTextLayoutFragment          // Per-paragraph layout info
  .layoutFragmentFrame        // CGRect position and size
  .rangeInElement              // NSTextRange of the fragment
NSTextContentStorage
  .offset(from:to:)           // NSTextRange → UTF-16 offset conversion
  .documentRange              // Full document range
```

### Gotchas Encountered
1. **`NSTextContainer` height must be 0 (unconstrained)** — setting it to
   `CGFloat.greatestFiniteMagnitude` causes layout issues. Zero means
   "lay out everything."
2. **`lineFragmentPadding` defaults to 5** — must explicitly set to 0 to get
   accurate width calculations matching the viewport.
3. **`fragment.textElement?.elementContentRange`** does not exist on
   `NSTextElement` in current SDK. Use `fragment.rangeInElement` instead.
4. **Layout fragments are per-paragraph**, not per-line. A long paragraph
   that wraps will be a single fragment with a tall frame. This is fine for
   page slicing since we compare fragment bottom vs viewport height.

## Known Limitations

1. **Paragraph-level granularity**: TextKit 2 enumerates fragments at the
   paragraph level. A paragraph taller than the viewport will be placed
   entirely on one page (overflowing). For VReader's use case (prose text),
   this is acceptable — paragraphs rarely exceed viewport height. If needed,
   a secondary pass could split oversized paragraphs using Core Text line
   enumeration.

2. **No attributed string styling beyond font**: The spike uses a single font
   for the entire text. Production code will need paragraph-level styling
   (indentation, heading sizes, margins between paragraphs).

3. **No image/attachment handling**: Pure text only. Inline images would need
   `NSTextAttachment` support.

4. **Main thread requirement**: `@MainActor` is required for TextKit 2 layout.
   For very large files, the layout pass could block the UI. Mitigation:
   paginate lazily (first few pages immediately, rest in background).

5. **Memory**: TextKit 2 holds the full attributed string plus layout data in
   memory. For 15MB files, this could be 30-50MB. The chunked loading approach
   (TXTChunkedLoader) could be adapted to feed content progressively.

## Decision: USE TextKit 2

TextKit 2 is the correct choice for VReader's paginated rendering engine because:

1. **Correct**: All 14 tests pass including CJK, mixed scripts, edge cases.
2. **Fast**: Sub-10ms for typical documents (500 lines).
3. **Deterministic**: Identical results across runs.
4. **Native CJK support**: No custom line-breaking logic needed.
5. **Standard API**: Maintained by Apple, will receive updates and optimizations.
6. **iOS 17+ only**: Aligns with VReader's minimum deployment target.

### Why NOT Core Text

Core Text would provide lower-level control but requires:
- Manual line breaking and paragraph handling
- Manual font/style attribute management
- Custom coordinate space transformations
- Significantly more code for the same result

TextKit 2 wraps Core Text internally and provides the right abstraction level
for paginated prose rendering.

## Next Steps

1. Promote `TextKit2Paginator` from spike to production code
2. Add paragraph style support (margins, indentation, heading sizes)
3. Integrate with `ReflowableTextSource` protocol for TXT/MD input
4. Add incremental re-pagination (cache layout, recalculate page boundaries)
5. Add oversized paragraph splitting for edge cases
6. Performance test with 15MB CJK file on physical device
