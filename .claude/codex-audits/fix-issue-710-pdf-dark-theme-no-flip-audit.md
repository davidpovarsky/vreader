---
branch: fix/issue-710-pdf-dark-theme-no-flip
threadId: 019e2c9f-f10f-7fa0-83a2-32c57691c294
rounds: 3
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Bug #198 / GH #710 — PDF Dark theme doesn't visibly flip

## Issue summary

`docs/bugs.md` Bug #198 / GitHub issue #710: user picks Dark theme in the reader settings (aA button); the chrome bar themes correctly but the **PDFView gutter** (area surrounding the rendered page) stays on PDFKit's default light gray. Visually the flip from Sepia → Dark is invisible because the rendered PDF page is still on a light-gray canvas. Same break for the Light → Dark transition.

Root cause: `PDFReaderHost` (in `vreader/Views/Reader/ReaderFormatHosts.swift`) accepts no `settingsStore` parameter and never threads theme to `PDFReaderContainerView` → `PDFViewBridge`. PDFView's `backgroundColor` is therefore never updated when the user switches reader theme.

## Fix shape

Wire `settingsStore: ReaderSettingsStore?` through three levels (Container → Host → Container → Bridge), then in `PDFViewBridge` apply `theme.backgroundColor` to `pdfView.backgroundColor` on mount and on theme change. Gated against `lastAppliedTheme` so unrelated `updateUIView` fires (page nav, scroll fraction, highlight pipeline) don't redundantly thrash.

## Changed files

```
vreader.xcodeproj/project.pbxproj                 |  4 ++
vreader/Views/Reader/PDFReaderContainerView.swift |  8 +-
vreader/Views/Reader/PDFViewBridge.swift          | 56 +++++++++++++++++++++
vreader/Views/Reader/ReaderContainerView.swift    |  3 +-
vreader/Views/Reader/ReaderFormatHosts.swift      |  6 ++-
vreaderTests/Views/Reader/PDFViewBridgeThemeTests.swift | (new)
```

## Round 1 — initial audit

| File:Line | Severity | Issue | Fix |
|---|---|---|---|
| `vreaderTests/Views/Reader/PDFViewBridgeThemeTests.swift:1` | Medium | Tests only cover the pure helper (`applyThemeBackground`); never exercise the actual regression path (`settingsStore.theme` mutation → `body` invalidation → `updateUIView`). A broken observation chain or `lastAppliedTheme` gating bug would still pass. | Add a test that hosts the view in SwiftUI, mutates a live `ReaderSettingsStore.theme`, and asserts `PDFView.backgroundColor` changes without remounting. |
| `vreader/Views/Reader/PDFViewBridge.swift:105` | Low | Optional-theme contract is only partially implemented. If a caller goes from a concrete `theme` to `nil`, `updateUIView` does nothing, so the PDFView keeps the last applied custom background. Not user-visible on the main path. | Either make `theme` non-optional end to end, or handle `nil` explicitly. |
| `vreader/Views/Reader/PDFViewBridge.swift:25` | Low | File is now 393 lines, over the repo's soft ~300 line cap. The bridge is accumulating responsibilities: document load, search highlight, selection, gestures, theming. | Split by concern (e.g. `PDFViewBridge+Coordinator.swift`, `PDFViewBridge+Search.swift`). |

**Round-1 verification by Codex of the wiring/types/observation chain**: confirmed `ReaderSettingsStore` is `@Observable @MainActor`, `ReaderTheme.backgroundColor: UIColor` is the right type, `PDFView.backgroundColor` accepts `UIColor`, `lastAppliedTheme` on the coordinator is safe on the main-thread UI paths, equality compare on `ReaderTheme` enum is correct, theme changes during document load are safe, rapid toggles are safe. No security issues, no duplicate logic, no dead code.

## Round 2 — fixes attempted, Medium still open

- Tried adding an `else if context.coordinator.lastAppliedTheme != nil { pdfView.backgroundColor = nil; ... }` branch. The current iOS 26.5 SDK exposes `PDFView.backgroundColor` as non-nullable `UIColor`, so `nil` assignment doesn't compile. Reverted the else branch and documented the concrete-theme → nil case as a non-production edge (ReaderContainerView always threads the live settingsStore; previews start nil with `lastAppliedTheme` nil so neither branch fires). Low **accepted with rationale**.
- Added `updateUIViewStateMachine_appliesOnlyOnThemeChange` test that simulates the state machine.
- File size Low **accepted as deferred refactor**.

Codex round-2 caught that the new test still **reimplemented** the algorithm locally instead of driving the production code path:

> "It validates the intended algorithm, not the shipped code path. Replace it with a test that invokes the real bridge update path, or extract the guard into a small production helper/state object and test that helper directly instead of duplicating the logic in the test."

## Round 3 — Medium closed

- Extracted the gated dispatch into a real production helper:

  ```swift
  static func applyThemeIfChanged(
      pdfView: PDFView,
      theme: ReaderTheme?,
      lastAppliedTheme: ReaderTheme?
  ) -> ReaderTheme? {
      guard let theme, lastAppliedTheme != theme else { return lastAppliedTheme }
      applyThemeBackground(to: pdfView, theme: theme)
      return theme
  }
  ```
- Both `makeUIView` and `updateUIView` now route through this helper:

  ```swift
  context.coordinator.lastAppliedTheme = Self.applyThemeIfChanged(
      pdfView: pdfView,
      theme: theme,
      lastAppliedTheme: context.coordinator.lastAppliedTheme
  )
  ```
- The integration test `applyThemeIfChanged_drivesProductionGuard` now drives the exact production helper that the bridge calls. Covers: initial mount, same-theme short-circuit (with sentinel-color check), sequential theme switches, nil-theme no-op. A future regression weakening the `lastAppliedTheme != theme` guard fails this test directly because the test invokes the production code path, not a reimplemented copy.

Codex round-3 verdict:

> "No new correctness findings. ... That closes the earlier Medium finding. The nil-theme rationale is still acceptable as documented. The only remaining note is the already-known maintainability concern: [PDFViewBridge.swift] is now 414 lines, over the repo's soft cap, but that remains a deferred refactor issue rather than a bug in this fix."

## Final disposition

- Round 1 Medium (test coverage gap): **CLOSED** — integration test now drives the real production helper.
- Round 1 Low (nil restoration): **ACCEPTED WITH RATIONALE** — SDK non-nullable + production path never goes nil after non-nil.
- Round 1 Low (file size, 393→414 lines): **DEFERRED** — out of scope for a behavior fix; PDFViewBridge split tracked as a future refactor.

## Test gate (Phase 5)

- PDFViewBridgeThemeTests: 6/6 pass (5 pure-helper tests + 1 integration test driving `applyThemeIfChanged`).
- Full unit suite (`-only-testing:vreaderTests`): pre-existing failures only, none introduced by this fix:
  - `BookFormatAZW3Tests` (2 failures) — Bug #176 pre-existing, AZW3 TTS not wired into `loadBookTextContent`.
  - `BookSourceHTTPClientTests` (~19 issues across ~6 test methods) — pre-existing MockURLProtocol shared-state flake (fails in isolation too, e.g. `fetchPage_concurrent_safe` recorded 5 issues on its own).
- No tests touching `PDFViewBridge.swift`, `PDFReaderContainerView.swift`, `ReaderFormatHosts.swift`, or `ReaderContainerView.swift` regressed.

## Verdict

**ship-as-is** with follow-up recommended (split PDFViewBridge.swift in a future refactor when it justifies its own PR).
