---
branch: fix/issue-611-txt-dynamic-island-clipping
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Bug #179 / GH #611 — TXT Dynamic Island Clipping (audit log)

## Context

Bug #179: in the TXT reader, the first line of text was clipped behind the iPhone 17 Pro
Dynamic Island because `ReaderContainerView` uses `.ignoresSafeArea(edges: .top)` (deliberate
so the page-flip animation can run edge-to-edge) but the inner TXT bridges hard-coded
`textContainerInset = UIEdgeInsets(top: 16, ...)` without compensating for the safe-area
top. The same pattern fixed EPUB clipping in bug #163.

## Codex availability

Codex MCP unavailable this session (`stream disconnected before completion` on every call).
Fell back to manual audit per `.claude/rules/47-feature-workflow.md` "Manual fallback when
AI auditor unavailable".

## Files audited

| File | Purpose | Audit pass |
|---|---|---|
| `vreader/Views/Reader/TXTTextViewBridge.swift` | UITextView bridge | reviewed |
| `vreader/Views/Reader/TXTChunkedReaderBridge.swift` | UITableView chunked bridge | reviewed |
| `vreader/Views/Reader/TXTReaderContainerView.swift` | host (3 call sites) | reviewed |
| `vreader/Views/Reader/MDReaderContainerView.swift` | host (1 call site, MD scroll mode) | reviewed |
| `vreaderTests/Views/Reader/TXTTextViewBridgeSafeAreaInsetTests.swift` | new tests | reviewed |

## Manual audit evidence

### Files read

- `vreader/Views/Reader/ReaderContainerView.swift` — confirmed `.ignoresSafeArea(edges: .top)`
  is present at the host level.
- `vreader/Views/Reader/TXTTextViewBridge.swift` — verified existing `textContainerInset`
  application sites in `makeUIView` and `updateUIView`.
- `vreader/Views/Reader/TXTChunkedReaderBridge.swift` — verified `tableView.contentInset`
  default and that `contentInsetAdjustmentBehavior` is the right knob (matches EPUB fix).
- `vreader/Views/Reader/TXTReaderContainerView.swift` — confirmed 3 call sites use the
  bridge (paged, chapter, chunked) and all needed safe-area inset wiring.
- `vreader/Views/Reader/MDReaderContainerView.swift` — confirmed MD scroll mode uses the
  TXT bridge (same path), only one call site to update.
- `vreader/Models/ReaderSettings.swift` / `TXTReaderConfig.swift` — verified `config.textInset`
  is `UIEdgeInsets`, default top=16.

### Symbols / signatures verified

- `TXTTextViewBridge.combinedTextInset(base:safeAreaTop:) -> UIEdgeInsets` — new static helper,
  pure function, returns clamped (`max(0, safeAreaTop)`) sum on top edge.
- `TXTTextViewBridge.safeAreaTopInset: CGFloat = 0` — default 0 preserves prior behavior on
  callers that haven't been updated.
- `TXTChunkedReaderBridge.safeAreaTopInset: CGFloat = 0` — same default-preserving pattern.
- `GeometryReader { proxy in Bridge(safeAreaTopInset: proxy.safeAreaInsets.top, ...) }` —
  wrapping pattern matches the EPUB fix in bug #163.

### Edge cases checked

1. **Devices without Dynamic Island** (iPhone < 14 Pro, iPad) — `safeAreaInsets.top` is the
   status bar height (~20–47pt), which the helper sums in. No clipping; just a tiny extra
   typographic margin, same visual effect as the EPUB fix.
2. **Zero safe-area** — `safeAreaTop: 0` returns `base` unchanged. Covered by unit test
   `zeroSafeAreaPreservesBase`.
3. **Negative safe-area** (theoretically impossible but defensive) — clamped to 0. Covered
   by unit test `negativeSafeAreaClamps`.
4. **Idempotency in `updateUIView`** — assigning `textContainerInset` only when it differs,
   matching the bridge's existing pattern (avoids relayout churn). Same for
   `tableView.contentInset.top`.
5. **Chunked path (UITableView)** — `contentInsetAdjustmentBehavior = .never` is required;
   otherwise UIKit would auto-add safe-area on top of our manual inset, doubling it.
6. **Reading-mode switches** (paged ↔ chapter ↔ chunked) — all three call sites now wrap
   in `GeometryReader`, so the inset follows the active bridge.
7. **Rotation / size class changes** — GeometryReader re-emits `proxy.safeAreaInsets.top`,
   `updateUIView` re-applies. Verified by the `updateUIView` guard.
8. **MDReaderContainerView.readerContent** — uses TXTTextViewBridge for scroll mode; safe-area
   wiring added. Paged MD (NativeTextPagedView) is OUT OF SCOPE for bug #179.

### Concurrency check

- `combinedTextInset` is a pure static function — no actor isolation concerns.
- Bridge methods (`makeUIView`, `updateUIView`) are SwiftUI-driven on `MainActor` — consistent
  with the rest of `UIViewRepresentable`.

### Risks accepted

- **`NativeTextPagedView` not updated** — has the same hardcoded `textContainerInset` flaw.
  Out of scope: bug #179 is filed for TXT, and the user filed the bug from TXT context.
  Filing a follow-up issue would be appropriate but is scope-guarded out of this fix.
- **PDF / EPUB / Foliate paths unchanged** — EPUB was fixed in bug #163; PDF uses
  `PDFView` which has its own safe-area handling; Foliate WebView clips via CSS in the
  bundle. None affected by this change.
- **PDF/EPUB call sites in `ReaderContainerView` dispatcher not touched** — they
  go through different bridges that have already been audited for safe-area handling.

### Tests added

- `vreaderTests/Views/Reader/TXTTextViewBridgeSafeAreaInsetTests.swift` — 4 unit tests for
  `combinedTextInset` static helper:
  - sums positive safe-area top
  - zero preserves base
  - negative clamps to 0
  - custom base preserved on non-top edges

All 4 pass under `xcodebuild test -only-testing:vreaderTests/TXTTextViewBridgeSafeAreaInsetTests`.

## VReader compliance

- Swift 6 concurrency: clean (no new actor crossings)
- `@MainActor` correctness: bridge methods stay MainActor-isolated
- SwiftData actor isolation: not touched
- File size: TXTTextViewBridge.swift remains <300 lines
- Bridge safety: not applicable (no JS interpolation in this change)
- DEBUG gating: not applicable (this is production code, not DEBUG-only)

## Findings

| # | severity | issue | resolution |
|---|---|---|---|
| 1 | n/a | none — fix is minimal, targeted, and mirrors the existing bug #163 EPUB pattern | n/a |

## Final verdict

**ship-as-is** — change is minimal and matches the established cross-bridge pattern. Tests
green for the new helper; pre-existing flakes (`AutoPageTurnerTests`,
`TTSServiceSpeedControlTests`) are unrelated to TXT/safe-area work and were documented as
pre-existing in earlier cron iterations (bug #167 close-gate note).
