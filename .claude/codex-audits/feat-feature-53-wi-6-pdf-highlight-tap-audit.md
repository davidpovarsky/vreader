---
branch: feat/feature-53-wi-6-pdf-highlight-tap
threadId: 019e2d03-ff20-74e0-a308-215302f7e1aa
rounds: 3
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Feature #53 WI-6 — PDF tap-on-highlight (FINAL WI)

## Summary

Final WI for Feature #53. PDFViewBridge's `handleTap` now hit-tests the renderer's `annotationMap` against the tap location; if a highlight is hit, the bridge posts `.readerHighlightTapped` + shows the inline `Delete Highlight` menu via `UIKitHighlightActionPresenter` + routes the action through `HighlightCoordinator.handleTapAction`. Miss/gutter taps still fall through to chrome-toggle. Active text selection still short-circuits the entire tap path (existing gate, preserved).

## Changed files

```
vreader/Views/Reader/PDFHighlightTapResolver.swift  (new, ~50 LOC)
vreader/Views/Reader/PDFViewBridge.swift            (+~50 LOC tap hit-test + presenter wiring + updateUIView rebinds)
vreader/Views/Reader/PDFReaderContainerView.swift   (+5 LOC presenter + action callback injection)
vreaderTests/Views/Reader/PDFHighlightTapResolverTests.swift  (new, 6 tests)
vreader.xcodeproj/project.pbxproj                   (xcodegen regen)
```

## Round 1

| File:Line | Severity | Finding | Resolution |
|---|---|---|---|
| PDFViewBridge.swift:401 | High | Posts `.readerHighlightTapped` but no production consumer wired → user-visible UX gap. | Round-2: added `highlightActionPresenter` + `onHighlightTapAction` parameters, mirroring TXT/EPUB. PDFReaderContainerView passes `UIKitHighlightActionPresenter()` + closure routing through `highlightCoordinator?.handleTapAction`. |
| PDFHighlightTapResolverTests.swift:15 | Medium | Tests cover pure resolver only; bridge control-flow (hit/miss/active-selection) not unit-tested. | Round-2 / Round-3: ACCEPTED with rationale — coordinator-mocking infrastructure for UITapGestureRecognizer + PDFView would be ~150 LOC for marginal coverage; Gate 5 device verify exercises the gesture path. |

## Round 2

Closed Round-1 High via full presenter wiring. Found new High:

| File:Line | Severity | Finding | Resolution |
|---|---|---|---|
| PDFViewBridge.swift:82 | High | `highlightCoordinator` is initialized later in PDFReaderContainerView's async `.task`. The closure captured at `makeUIView` time would see nil forever → Delete a no-op. TXT/EPUB rebind these on every `updateUIView` for exactly this reason. | Round-3: added rebinds in `updateUIView` for `highlightRenderer`, `highlightActionPresenter`, `onHighlightTapAction`. Once `highlightCoordinator` initializes, SwiftUI re-evaluates body → bridge constructor with non-nil closure capture → `updateUIView` rebinds → Delete works. |

## Round 3

Codex verdict: **No findings. Ship-as-is.** Control flow + API choices + the rebind pattern all confirmed correct. The remaining test-scope gap is documented as future test-infra improvement, not a blocker.

## Test gate (Gate 3)

- `PDFHighlightTapResolverTests`: 6/6 pass.
- `PDFViewBridgeThemeTests` (adjacent suite touching same file): 6/6 pass — no regressions.
- Build clean.

## Gate 5 device-verification plan

This is the **final WI** for Feature #53. Gate 5 = full acceptance pass:

1. Open a PDF with at least one persisted highlight.
2. Tap on the highlighted text.
3. **Expected**: inline `Delete Highlight` menu appears anchored near the tap.
4. Tap Delete.
5. **Expected**: highlight removed from visual rendering + persistence (verified by tapping again — no menu).
6. Miss tap (outside any highlight) → chrome toggles as before.
7. Active text selection → tap inside selection → no menu (preserves create-new-highlight UX).

Once verified, Feature #53 flips IN PROGRESS → DONE (Gate 6 merge), then DONE → VERIFIED (Gate 5b final acceptance evidence file).

## Verdict

**ship-as-is.** Final WI complete. After merge, Feature #53 is feature-complete for all 5 reader formats (TXT/MD/EPUB via prior WIs; Foliate notification-only via WI-5 with Bug #199 tracking the consumer wiring; PDF via this WI with full presenter wiring).

Feature #53's row will flip:
- IN PROGRESS → DONE on merge (final WI's PR completes the implementation set).
- DONE → VERIFIED in a follow-up after a full acceptance device verify pass against all 5 formats. Foliate-half blocked by Bug #199 until its consumer wiring lands.
