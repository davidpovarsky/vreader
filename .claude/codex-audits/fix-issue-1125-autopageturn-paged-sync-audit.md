---
branch: fix/issue-1125-autopageturn-paged-sync
threadId: 019e4aec-a931-7b42-8967-eb056608a37b
rounds: 1
final_verdict: ship-as-is
date: 2026-05-21
---

# Codex Audit — Bug #258 / GH #1125 (auto-page-turn paged view sync)

- **Branch**: `fix/issue-1125-autopageturn-paged-sync`
- **Auditor**: Codex MCP (gpt-5.2 default, ChatGPT subscription auth), read-only sandbox
- **Thread**: `019e4aec-a931-7b42-8967-eb056608a37b`
- **Rounds**: 1
- **Verdict**: **ship-as-is**

## Scope audited

The view-sync fix for Bug #258: `AutoPageTurner`'s timer advanced the navigator's
internal page but never synced the observable `uiState.pagedCurrentPage` that drives
the `NativeTextPagedView` render + `snapshot.position`. Fix routes each timer tick
through a new `onAdvance` callback that runs the same `syncPagedState()` +
`updateScrollPosition()` the `.readerNextPage` observer does, MINUS that observer's
`pause()` (which would otherwise halt auto-advance after one tick — the FATAL hazard
in the bug row's fix-direction (a)).

Files: `AutoPageTurner.swift`, `TextReaderUIState.swift`, `MDReaderContainerView.swift`,
`TXTReaderContainerView.swift`, `AutoPageTurnerTests.swift`.

## Findings

### Critical / High / Medium
None.

### Low (1)
- **`TextReaderUIState.swift` doc comment** said the container installs
  `onAutoAdvancePersist` "once in `onAppear`", but the install is actually in the
  body-level `.task`. **Fixed** in this branch (comment now says `.task`).

## Auditor's confirmations (the audit focus areas)

1. **No double-advance / double-sync** — the timer path and the tap-zone
   `.readerNextPage` path are cleanly separate. `onAdvance` is invoked ONLY from
   `AutoPageTurner.scheduleTimer()` after `nextPage()`; the `.readerNextPage`
   observers do NOT call it.
2. **No feedback loop** — the `onAdvance → syncPagedState() → updateScrollPosition()
   → makeLocator() → viewModel.totalProgression change → container
   `.onChange(of: totalProgression)` → `.readerPositionDidChange`` chain does NOT
   post `.readerNextPage` or re-enter the turner.
3. **Last-page correctness** — the `nav.currentPage >= nav.totalPages - 1` guard
   returns before `nextPage()`, so `onAdvance` fires only on a real advance, never on
   the auto-stop. Correct for the current `BasePageNavigator` / `NativeTextPageNavigator`.
4. **Concurrency / @MainActor** — no main-actor race that would let `stop()` cancel
   "too late" and still fire `onAdvance` afterward. (`AutoPageTurner` is
   `@MainActor @Observable`; the timer `Task` and the `@MainActor () -> Void` closure
   are same-isolation.)
5. **Retain cycles** — `[weak self]` on `turner.onAdvance` (self=uiState owns turner)
   and `[weak viewModel]` on `onAutoAdvancePersist` are correct; no strong cycle, no
   use-after-free on teardown mid-tick.

## Disposition

`ship-as-is`. The one Low (doc nit) is fixed in-branch. No follow-up required.
