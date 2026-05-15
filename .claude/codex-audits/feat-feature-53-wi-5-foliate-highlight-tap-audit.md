---
branch: feat/feature-53-wi-5-foliate-highlight-tap
threadId: 019e2cee-3ee9-7f12-b212-5d7cafe61fc6
rounds: 3
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Feature #53 WI-5 — Foliate (AZW3/MOBI) highlight-tap regression fix

## Summary

WI-5 swaps the misused `.readerHighlightRequested` post (silently no-op'd by the create-path validator since WI-1) for the correct `.readerHighlightTapped` event, with CFI→UUID resolution via a new `FoliateHighlightTapResolver`. Inline-menu presenter wiring (the user-visible piece) is explicitly out of WI-5 scope per the plan; tracked as follow-up Bug #199 / GH #733.

## Changed files

```
vreader/Services/Foliate/FoliateHighlightTapResolver.swift  (new)
vreader/Views/Reader/FoliateSpikeView.swift                 (annotation-show handler + observer)
vreader/Views/Reader/FoliateReaderContainerView+Highlights.swift  (dormant-path mirror)
vreader/Views/Reader/ReaderNotifications.swift              (.foliateAnnotationTapRequested)
vreaderTests/Services/Foliate/FoliateHighlightTapResolverTests.swift  (new, 6 tests)
docs/bugs.md                                                (row #199 added)
vreader.xcodeproj/project.pbxproj                           (xcodegen regen)
```

## Round 1 — initial audit

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| FoliateReaderContainerView+Highlights.swift:55 | Critical | Fix on dormant `FoliateReaderContainerView` path; live AZW3/MOBI dispatch is `FoliateSpikeView` (ReaderContainerView.swift:523) which has no `case "annotation-show"`. | Round-2: wired Spike's `handleMessage` to post a new internal `.foliateAnnotationTapRequested` notification + observer in Spike's outer body that resolves and posts `.readerHighlightTapped`. |
| FoliateReaderContainerView+Highlights.swift:67 | High | No production consumer of `.readerHighlightTapped` on Foliate path → user tap still has no visible effect. | Round-3: ACCEPTED with documented gap; filed Bug #199 / GH #733 for consumer wiring. Plan explicitly defers presenter wiring to future iteration. |
| FoliateReaderContainerView+Highlights.swift:61 | Medium | `try? await persistence.fetchHighlights(...)` swallows persistence errors. | Round-2: replaced with `do/catch` + `Logger.error(...)`; applied to both Spike (live) and Host (dormant) paths. |
| FoliateHighlightTapResolverTests.swift:55 | Medium | Tests cover only pure resolver, not the end-to-end JS → Coordinator → resolver → notification flow. | Round-3: ACCEPTED — heavy WKScriptMessage/SwiftUI mock infrastructure (~200 LOC) for marginal coverage. Gate 5 device verify exercises the end-to-end. |
| FoliateReaderContainerView+Highlights.swift:56 | Low | `FoliateNavigationHelper.isValidNavigationTarget` is misleadingly named — only a non-empty-CFI check. | Round-3: ACCEPTED — out of WI-5 scope; rename touches multiple call sites. Tracked as future refactor. |

## Round 2 — Critical + Medium closed

- Live Spike path now handles `annotation-show`:
  - `Coordinator.handleMessage` has new `case "annotation-show":` extracting `value` (CFI) + `fingerprintKey` and posting `.foliateAnnotationTapRequested`.
  - Made `Coordinator.fingerprintKey` non-DEBUG (production path needs it; previously DEBUG-only for the DebugBridge registry). `readerToken` stays DEBUG-only.
  - Outer `FoliateSpikeView.body` adds `.onReceive(.foliateAnnotationTapRequested)` that filters by fingerprintKey, fetches highlights via `PersistenceActor` (in scope via `@Environment(\.modelContext)`), resolves CFI → UUID, posts `.readerHighlightTapped` event with `sourceRect: .zero`.
- `do/catch + log` applied to both Spike (live) and dormant Host paths.

Round-2 raised: High (no production consumer) + Low (per-reader instance token isolation).

## Round 3 — High + Low accepted with rationale

- High (no consumer): Filed Bug #199 / GH #733 with concrete fix direction (mirror EPUB pattern from `EPUBWebViewBridgeCoordinator.handleHighlightTapMessage` — thread `highlightActionPresenter` + `onHighlightTapAction` into `FoliateSpikeView`, plus `foliate-host.js` rect forwarding via `range.getBoundingClientRect()`). Could land as WI-5b or standalone bug fix. WI-5 is internally consistent without it — the notification firing is the contract change; UI surfacing follows.
- Low (per-reader token): Deferred — multi-Foliate-readers-of-same-book is extraordinarily rare; vreader presents one reader at a time. Revisit if split-screen / PiP support is added.

**Final Codex verdict**: ship-as-is. The scope is coherently bounded: WI-5 ships the regression fix + resolver + notification post; user-visible UI follows in Bug #199.

## Test gate (Gate 3)

- `FoliateHighlightTapResolverTests`: 6/6 pass.
- `FoliateMessageParserTests` (adjacent suite): 25/25 pass — no regressions.
- Build: clean, no errors.

## Gate 5 device-verification plan

Verifiable end-to-end on iPhone 17 Pro Simulator:

1. Open an AZW3 book (e.g., bundled `mini-azw3.azw3`).
2. Select text → create highlight.
3. Tap the highlighted text.
4. **Expected (today)**: `.readerHighlightTapped` posts with correct UUID — observable by:
   - Adding a temporary `addObserver(forName: .readerHighlightTapped)` in a debug branch, OR
   - DebugBridge eval that queries notification log (if available).
   - **NOT observable as a visible UI change** — that's Bug #199.
5. Confirm `.readerHighlightRequested` does NOT fire (regression fix verified).

The visible behavioral contract WI-5 changes is internal: which notification fires on highlight-tap. The user-visible inline-menu surface is Bug #199's contract.

## Verdict

**ship-as-is** with follow-up Bug #199 / GH #733 explicitly tracking the user-visible consumer wiring. WI-5's plan describes exactly this scope at `dev-docs/plans/20260515-feature-53-tap-on-highlight.md:136`.
