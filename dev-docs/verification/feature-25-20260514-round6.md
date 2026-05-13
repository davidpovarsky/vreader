---
kind: feature
id: 25
status_target: VERIFIED
commit_sha: 5519d2eee8e6ed04dd7478373082a8697046bbc0
app_version: 3.21.32 (build 309)
date: 2026-05-14
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: in-process production `TapZoneOverlay` + `TapZoneDispatcher` + `UnifiedTextRenderer` (no mocks)
result: partial
---

## Summary

Verify-cron iteration attempt at closing feature #25's deferred slice — **Left/Right tap-zone page-turn dispatch** — using the war-and-peace.txt fixture as an alternative to the multi-page-EPUB fixture round-5 was blocked on.

Outcome: **still blocked**, but on a different invariant than expected. TXT is capability-gated OUT of Unified mode (bug #158 fix), so the Reading Mode picker doesn't appear in the Reading Settings panel for TXT, and the user has no path to enter Unified mode. `TapZoneOverlay` is only installed in `ReaderUnifiedDispatch.unifiedReaderView` — Native TXT (TXTTextViewBridge / UITextView) has no tap-zone overlay. Tapping the right zone in the running Native-TXT view toggles chrome (via the bridge's gesture handler) rather than firing the `.nextPage` notification.

## Acceptance criteria

| Criterion | Slice | Result |
|---|---|---|
| Center-tap → toggle chrome on Unified render | Round-5 (`feature-25-20260510-round5.md`, mini-epub3 + Unified mode) — bidirectional confirmed | pass (prior round) |
| Right-tap → `.nextPage` advances page on Unified render | DEFERRED round-5 (mini-epub3 single column); **this round attempted on war-and-peace TXT** → blocked: TXT has no Unified path | deferred (blocker confirmed) |
| Left-tap → `.previousPage` retreats page on Unified render | Same as right-tap | deferred (blocker confirmed) |

## Why partial

Three independent blockers identified across rounds 5 + 6, all fixture-class:

1. **Multi-page EPUB**: `mini-epub3` fits in single column (`scrollWidth === clientWidth` per feature #21 finding) — `EPUBPaginationHelper.navigateToPageJS` has nothing to advance to.
2. **TXT in Unified mode** (this round): TXT was capability-gated out of `.unifiedReflow` by bug #158 fix (`FormatCapabilities.swift:txt` case excludes `.unifiedReflow`; `reflowableBase` no longer grants it). `ReaderSettingsPanel.shouldShowReadingModeSection(for:)` hides the picker when format lacks `.unifiedReflow`. The user cannot reach Unified mode → tap-zone overlay never installed for TXT → tap-right falls through to the bridge's content-tap → chrome toggles.
3. **No MD multi-page fixture**: MD has `.unifiedReflow` but no fixture larger than 1 page at default font size (`mini-md` fixture doesn't exist; the only MD fixture in `DebugFixtureCatalog.entries` is the tiny `mdTOC` 678-byte test asset used for feature #31 round-3 work).

## Commands run

```bash
# Boot iPhone 17 Pro Sim (already running from prior session)
# Install merged-build at v3.21.32 (commit 5519d2e)
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/vreader-hdhlhcqmxppsadhececcxeadpkvz/Build/Products/Debug-iphonesimulator/vreader.app
xcrun simctl launch booted com.vreader.app

# Seed war-and-peace.txt
xcrun simctl openurl booted "vreader-debug://reset"
xcrun simctl openurl booted "vreader-debug://seed?fixture=war-and-peace"
xcrun simctl openurl booted "vreader-debug://open?bookId=txt:bd8285a80f01df96dedd20a02178043afb85c0b499127e300baf57b7f1ed7508:1705"

# Drove the simulator via computer-use:
# 1. Tap center @ (262, 400) in Mac coords → chrome toggled OFF (UITextView's content-tap, not TapZoneOverlay)
# 2. Tap right @ (361, 400) → chrome toggled BACK ON. Page indicator unchanged ("1 / 4")
# 3. Tap AA @ (390, 151) → Reading Settings sheet appears
# 4. Drag-scroll sheet content 3× to reach the bottom
# 5. Observed: Theme / Custom Background / Scroll-Paged / Font Size / Line Spacing / Font /
#    CJK Character Spacing / Simp→Trad-Trad→Simp / Custom Settings / Preview — NO Reading
#    Mode section. Picker is correctly hidden per bug #158 capability gate.

# Screenshot: dev-docs/verification/artifacts/feature-25-r6-txt-no-reading-mode-picker-20260514.png
```

## Observations

- **The capability-gate is doing its job**. The Reading Mode picker is correctly hidden for TXT because Unified-TXT is broken (bug #158 root cause: truncation, missing chrome, no TOC, toggle-blank). Re-opening it for verification would require fixing bug #158 first — feature-class scope, not verification-cron scope.
- **TXT bridge's content-tap fires on plain tap**, regardless of x-position. That's why the right-tap toggled chrome instead of advancing. This is the documented Native-TXT behavior — tap toggles chrome via `.readerContentTapped` notification observed in `TXTReaderContainerView` — not a bug.
- **The TXT paged-style footer** ("1 / 4 Previous/Next") is the universal navigation bar, not paged content. War-and-peace.txt is rendered via `chapterReaderContent` (4 chapters per bug #173 fixture fix). "Previous/Next" navigates chapters, not pages within a chapter.
- The bug #179 fix that landed earlier this session (TXT Dynamic Island safe-area inset) is visibly working on this view — title "War and Peace" clears the DI cleanly. Unrelated to feature #25 but observable in the same screenshot.

## Three unblock paths (none verify-cron scope)

(a) **Add a multi-page MD fixture** (`mini-md-multi-page.md`, ≥5KB) to `vreader/Resources/DebugFixtures/` + register in `DebugFixtureCatalog`. MD has `.unifiedReflow`, so the Reading Mode picker would appear, user could switch to Unified, tap zones would exercise `TapZoneOverlay` end-to-end. Minimum-risk path; small feature-class change.

(b) **Add a multi-page EPUB fixture** with content that overflows a single column — would unblock the original round-5 deferral path. Larger payload but more representative of real EPUB usage.

(c) **Wait for bug #158 proper fix** — restoring Unified-TXT renderer would let war-and-peace.txt exercise tap zones. Feature-class scope, multi-PR.

The IDEA-status feature row for "multi-page Unified-capable fixture for tap-zone verification" should be filed against feature #45's verification-harness sweep, since that's where fixture-catalog extensions belong by convention.

## Artifacts

- `dev-docs/verification/artifacts/feature-25-r6-txt-no-reading-mode-picker-20260514.png` — screenshot of war-and-peace.txt open with the AA toolbar accessible but no Reading Mode picker in the Settings sheet (confirming capability gate).

## Status

Tracker row #25 stays **DONE**. Flip to **VERIFIED** still gated on multi-page Unified-capable fixture (paths a/b/c above).
