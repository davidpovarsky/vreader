---
branch: fix/issue-1136-azw3-toc-nav-wiring
threadId: 019e4cd9-e482-7860-986f-fd2445eb1717
rounds: 2
final_verdict: ship-as-is
date: 2026-05-22
---

# Codex Audit — Bug #262 / GH #1136

AZW3/MOBI live Foliate reader: bottom-chrome Contents opens an empty TOC +
Notes/TOC row taps don't navigate into content. Fix wires the live
`FoliateBilingualContainerView` path to (A) capture the `book-ready` TOC and
feed `ReaderContainerView.tocEntries`, and (B) respond to
`.readerNavigateToLocator` (→ `readerAPI.goTo`) + produce
`.readerPositionDidChange`.

## Changed files

- `vreader/Services/Foliate/FoliateNavSeek.swift` (NEW pure helper)
- `vreader/Views/Reader/FoliateTOCAvailableObserver.swift` (NEW ViewModifier)
- `vreader/Services/Foliate/FoliateTOCConverter.swift` (round-1 fix: skip empty-href nodes)
- `vreader/Views/Reader/FoliateSpikeView.swift` (book-ready TOC forward + seek-target observer + relocate position-change)
- `vreader/Views/Reader/FoliateBilingualContainerView.swift` (TOC convert relay + nav relay)
- `vreader/Views/Reader/ReaderContainerView.swift` (TOC observer modifier)
- `vreader/Views/Reader/ReaderNotifications.swift` (3 new notification names)
- `vreaderTests/Views/Reader/FoliateTOCNavWiringTests.swift` (17 RED→GREEN tests)

## Round 1 — findings (2 Medium)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| FoliateNavSeek.swift:63 | Medium | `positionLocator` dropped the relocate `fraction`, so the new `.readerPositionDidChange` gave the AI path no usable position. `AIContextExtractor` treats `.azw3` like EPUB and reads `locator.progression` (AIContextExtractor.swift:154); a nil progression falls back to 0.0, pinning AI context to the book start. | **Fixed.** `positionLocator` now takes `fraction:` and threads it (clamped to 0...1, non-finite dropped) into `progression` + `totalProgression` via `Locator.validated`. Call site passes `parsed.fraction`. Regression tests `positionLocatorCarriesFraction` + `positionLocatorClampsFraction` added. |
| FoliateTOCConverter.swift:44 | Medium | TOC conversion accepted empty `href` values (foliate-host.js serializes a missing href as `''`), producing tappable TOC rows whose navigation no-ops (`FoliateNavSeek.navigationTarget` rejects empty hrefs) — a "row tap does nothing" class of bug for non-navigable parent TOC nodes. | **Fixed.** `flatten` now trims `item.href` and only emits a `TOCEntry` when both label and href are non-empty, while STILL recursing into `subitems` so clickable children of a non-navigable parent survive. Regression tests `tocConverterSkipsEmptyHrefParent` + `tocConverterSkipsWhitespaceHref` added. |

Round 1 also confirmed clean: the TOC wiring reaches `tocEntries`, row taps reach `readerAPI.goTo`, JS escaping is sufficient for a single-quoted literal, the seek-target observer teardown is correct, the scrubber path does not form a seek loop, and the eager `ensureTOCReady()` does not clobber the live TOC (azw3 file-builder returns `[]` immediately while `book-ready` arrives later from WebView load).

## Round 2 — verification

**ship-as-is.** Both fixes verified correct:

1. FIX 1 lands in the field that matters — `AIContextExtractor` reads
   `locator.progression` (not `totalProgression`) for `.azw3`
   (AIContextExtractor.swift:154, :208). Mirroring into `totalProgression` is
   also correct/beneficial for generic progress consumers.
2. FIX 2 preserves child depth (`flatten(..., level: level + 1, ...)` still
   runs when the parent is skipped) and `sequenceIndex` density (only
   increments for emitted rows). No existing converter test relied on
   empty-href emission; the new tests close that gap.
3. No new regression, Sendable, or actor-isolation issue introduced. The
   clamp/validate interaction is sound.

## Summary verdict

Two independent Codex rounds. Round 1 surfaced 2 Medium findings (AI-context
progression loss; empty-href dead TOC rows); both fixed with regression tests.
Round 2 verdict: **ship-as-is** — zero open Critical/High/Medium/Low findings.
