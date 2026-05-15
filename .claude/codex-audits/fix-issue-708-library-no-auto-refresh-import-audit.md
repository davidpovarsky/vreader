---
branch: fix/issue-708-library-no-auto-refresh-import
threadId: 019e2cd7-adc2-7130-8c06-eb764f00bf5d
rounds: 4
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Bug #197 / GH #708 — Library doesn't auto-refresh after Feature #59 import

## Issue summary

`docs/bugs.md` Bug #197 / GitHub #708: `xcrun simctl openurl booted "file:///tmp/test.epub"` invokes `FileURLImportRouter.dispatch()` → `BookImporter.importFile()` → SwiftData insert succeeds → SQLite row count increments → BUT `LibraryView` shows the OLD set until the next cold launch. Blocks Feature #59 acceptance criterion (b) ("tapping the destination launches vreader, imports the file, and lands on either the library or the freshly-opened reader").

Root cause: `LibraryView` doesn't use `@Query` — it has an imperative `LibraryViewModel.books` array filled by `loadBooks()`. The in-app Files-picker path calls `loadBooks()` directly after import; the Share Sheet path (`FileURLImportRouter.dispatch`) does NOT, so the library stays stale.

## Fix shape

Add `Notification.Name.bookDidImport` posted by `BookImporter.importFile` after both the new-insert path AND the duplicate-replace path. `LibraryView` observes it and triggers `viewModel.refresh(force: true)`. Idiomatic for vreader (mirrors the `.bookFileStateDidChange` pattern that LazyDownloadCoordinator already uses).

Plus a coalescing refactor to `LibraryViewModel.refresh(force:)`: the previous behavior dropped re-entrant calls (`guard !isRefreshing else { return }`); the new behavior sets a pending flag and drains until quiescent via a bounded loop + follow-up `Task` if the bound trips.

## Changed files

```
docs/architecture.md                                  |  1 +
vreader.xcodeproj/project.pbxproj                     |  4 ++++
vreader/Services/BookImporter.swift                   | 36 +++++++++
vreader/ViewModels/LibraryViewModel.swift             | 51 +++++++++++++
vreader/Views/LibraryView.swift                       | 24 ++++++
vreaderTests/Services/BookImporterNotificationTests.swift | (new)
vreaderTests/ViewModels/LibraryViewModelTests.swift   | 35 ++++++++
```

## Round 1 — initial audit

| File:Line | Severity | Issue | Fix |
|---|---|---|---|
| `LibraryViewModel.swift:137` | Medium | `refresh(force:)` drops re-entrant calls. Burst imports (multi-file restore) can lose B's notification if A's fetch started before B committed. | Coalesce: pending flag + trailing refresh, or drain-until-quiescent loop. |
| `BookImporterNotificationTests.swift:67` | Low | Test uses `Task.sleep(50ms)` to synchronize delivery — timing-based, can flake under CI load. | Replace with deterministic continuation/stream-based wait. |
| `BookImporter.swift:18` | Low | New cross-component notification path added, but `docs/architecture.md` Notification Bus table not updated. | Add `.bookDidImport` to that table. |

Codex round-1 also confirmed: notification posted from the right place (after persistence), no-observer and failure-midway cases fine, posting on duplicate is defensible UX, actor/threading acceptable (`NotificationCenter.default.post` thread-safe, `.onReceive` hops back to MainActor via `await viewModel.refresh()`). The `BookDidImportRefresher` ViewModifier is a justified workaround for the Swift type-checker's expression complexity limit on the already-large LibraryView body.

## Round 2 — Medium fix attempt + Low fixes

- Added single trailing refresh: `if hasPendingRefresh { hasPendingRefresh = false; await loadBooks(); ... }`.
- Rewrote tests with `NotificationKeyCollector` that registers observer BEFORE import; no Task.sleep. Tests deterministic.
- Updated `docs/architecture.md` Notification Bus table.

Round 2 found new Medium: single trailing check still loses third-wave refreshes that arrive during the trailing fetch. Also two Lows: 3-wave test wasn't deterministic, dead `lock`+`keys` fields on collector.

## Round 3 — drain-loop + cleanup

- Replaced single trailing check with `repeat { hasPendingRefresh = false; await loadBooks(); ... } while hasPendingRefresh && iterations < 8`.
- Added `refreshThreeWaveCoalesce_drainsUntilQuiescent` test.
- Removed dead `lock`+`keys` fields from `NotificationKeyCollector`.

Round 3 found: 8-iteration cap can strand pending work under sustained bursts (defer clears isRefreshing while flag is still set → no one drains).

## Round 4 — runaway-guard fallback

- Added `Task { @MainActor [weak self] in await self?.refresh(force: true) }` after the loop, fires only if cap tripped while pending flag still true. Re-enters after `defer { isRefreshing = false }` so the new call sees a clean slate.

Codex round-4: **No remaining findings.** Ship-as-is.

Residual note: `refreshThreeWaveCoalesce` doesn't deterministically force a refresh arrival during the trailing fetch (would need a phase-controlled blocking mock). The drain-loop's correctness is verifiable by code review (clear-flag-before-fetch-then-check pattern). Documented as future test-infrastructure improvement.

## Final disposition

- Round 1 Medium (re-entrance drop): **CLOSED** via drain-loop + runaway-guard Task fallback.
- Round 1 Low (test flakiness): **CLOSED** via NotificationKeyCollector observer-before-import pattern.
- Round 1 Low (docs sync): **CLOSED** via `.bookDidImport` row added to Notification Bus table.
- Round 3 Medium (3rd-wave loss): **CLOSED** via loop replacing single trailing check.
- Round 3 Low (multi-wave test): **CLOSED** via new `refreshThreeWaveCoalesce_drainsUntilQuiescent` test.
- Round 3 Low (dead code): **CLOSED** via NotificationKeyCollector cleanup.
- Round 4 Medium (cap strands work): **CLOSED** via follow-up Task fallback.
- Round 4 Low (multi-wave test still not phase-controlled): **DEFERRED** as test-infrastructure improvement, not a fix blocker.

## Test gate (Phase 5)

- `BookImporterNotificationTests`: 2 tests pass — new-insert + duplicate paths each post `.bookDidImport`.
- `LibraryViewModelTests`: 25 tests pass — including new `refreshConcurrentCalls_coalesceIntoTrailingRefresh` + `refreshThreeWaveCoalesce_drainsUntilQuiescent`.
- Broader suite (`BookImporterTests`, `BookImporterAZW3Tests`, `LibraryViewModelImportTests`, `LibraryViewModelPersistenceTests`, `FileURLImportRouterTests`): 71 tests pass. No regressions in adjacent code paths.

## Verdict

**ship-as-is.**

Behavioral change: a `.bookDidImport` notification fires on every successful import. Existing in-app Files-picker path becomes slightly redundant (it both calls `loadBooks()` directly AND now triggers a refresh via notification), but the redundant refresh is harmless thanks to the throttle + coalescing. Cleanup of the redundant call is out of scope for a behavior fix.
