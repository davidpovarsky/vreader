---
branch: fix/issue-1116-debugbridge-detent
threadId: 019e4e29-945e-76e0-b7e4-84ee6cfbfa50
rounds: 2
final_verdict: ship-as-is
date: 2026-05-22
---

# Codex audit — fix/issue-1116-debugbridge-detent (Bug #256 / GH #1116)

DebugBridge `present` command gains an `ai`-only `detent=medium|large` param to
reveal the below-`.medium`-fold Translate result card CU-free (unblocks Feature
#65 / GH #823 row 11).

- **Auditor**: Codex MCP (thread `019e4e29-945e-76e0-b7e4-84ee6cfbfa50`), read-only sandbox.
- **Author/auditor separation**: Codex is a separate process from the implementing Claude Code session (Gate-4 invariant satisfied).
- **Subject**: commit `59c391df` + the round-1 fix-up diff (since `59c391df`).

## Round 1 — 1 Medium, 0 Critical/High

**Medium — detent leak across reopen** (`ReaderContainerView.swift` AI sheet):
the DEBUG-only `aiPanelDetent` `@State` persists across dismiss; only the
DebugBridge present path reset it to `.medium`. So in a DEBUG build, after a
`present?sheet=ai&detent=large` open, a later *normal* AI open (toolbar /
selection-translate / `readerOpenAITranslate`) would reopen at `.large`,
violating "default `.medium` preserved" for subsequent default opens.
→ **Fixed**: the AI sheet's `.sheet(isPresented:$showAIPanel, onDismiss:{…})`
closure now resets `aiPanelDetent = .medium` under `#if DEBUG` on every
dismiss. DEBUG-only (the binding only exists in DEBUG; Release has no detent
state, so zero Release impact).

**Low — test coverage gap**: `bookmarks`-with-detent rejection was enforced in
code but not explicitly tested.
→ **Fixed**: added `test_parse_presentBookmarksWithDetent_throwsInvalidParam`
+ an exhaustive `test_parse_presentDetentRejectedForEverySheetExceptAI`
(toc/highlights/settings/bookmarks reject; ai accepts).

Dimensions reported clean in round 1:
- **DEBUG-gating / Release leak**: clean. `SheetDetent`, `supportsDetent`,
  the bridge protocol change, the observer + `Optional<SheetDetent>` extension
  all live in `#if DEBUG` files; `aiPanelDetent` is `#if DEBUG` `@State`. The
  only cross-config type is the `AIReaderPanelDetents` view modifier, which is
  intentionally present in both configs (it's the real production
  `presentationDetents` wrapper). (Confirmed by a Release build + binary
  `strings`: `SheetDetent`/`aiPanelDetent`/`supportsDetent` absent; the only
  DebugBridge-pattern hit is the SEPARATE pre-existing `LibraryDebugBridgeObservers`,
  already tracked as Bug #254 / GH #1110 — not introduced by this PR.)
- **No parallel presentation path**: clean. One notification → `DebugPresentSheetEffect`
  → the SAME `showAIPanel` / `presentationDetents(selection:)` state the real UI uses.
- **Param validation**: clean. `medium|large` accepted; unknown/empty/duplicate
  rejected; non-`ai` detents rejected via `SheetKind.supportsDetent`.
- **Concurrency / @MainActor**: clean. Dispatch + observer + `@State` mutation
  stay on the main actor; the optional-extension mapping is pure.
- **Fix intent**: confirmed `present?sheet=ai&tab=translate&detent=large` sets
  the detent before `showAIPanel = true`, and `.large` is in the declared
  detent set, so the sheet mounts at `.large` and exposes `translationResultCard`.

## Round 2 — No findings

Verdict: **`ship-as-is`**. The Medium is closed (dismiss reset restores the
production default after every completed dismissal; no race with the debug
present path — the explicit detent write still precedes `showAIPanel = true`,
and the dismiss reset runs after the prior presentation tears down). No new
issues from the dismiss-reset change. The added rejection coverage is sound.

## Test gate
Full `vreaderTests` suite green (443 tests, 0 failures) on iPhone 17 Pro
(iOS 26.5 sim, `-parallel-testing-enabled NO`, `-derivedDataPath build/issue-1116`).
New tests: 12 parser (`DebugCommandTests`), 1 dispatch (`DebugBridgeTests`),
1 userInfo + omission (`RealDebugBridgeContextTests`), 3 effect-resolve
(`DebugPresentSheetEffectTests`).
