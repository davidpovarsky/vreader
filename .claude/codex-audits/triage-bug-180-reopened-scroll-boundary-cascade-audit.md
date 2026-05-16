---
branch: triage/bug-180-reopened-scroll-boundary-cascade
bug: 180
date: 2026-05-16
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: reopens Bug #180 in `docs/bugs.md` after the user reported the fix (PR #681, commit 5f75fde) regressed TXT scroll-mode reading. Adds a regression comment to GH #614. No Swift source changes. No test changes.

## Audit

No logic to audit. The reopen entry is grounded in code-read evidence:

- `git show 5f75fde --stat`: the #180 fix touched `TXTViewConfig.swift` (protocol), `TXTTextViewBridgeCoordinator.swift` (boundary detection), `TXTReaderViewModel.swift` (chapter nav), plus tests.
- `TXTTextViewBridgeCoordinator.swift:378-401`: `sendScrollPosition` is the funnel for `scrollViewDidEndDecelerating` + `scrollViewDidEndDragging(decelerate:false)`. It computes `maxOffset = contentSize.height - bounds.height`; when `maxOffset > 2 * boundarySlack` (0.5), it fires `didScrollPastBottomBoundary()` if `offset >= maxOffset - boundarySlack`, or `didScrollPastTopBoundary()` if `offset <= boundarySlack`.
- `TXTReaderViewModel.swift:651-658`: `didScrollPastBottomBoundary()` → `goToNextChapter()`; `didScrollPastTopBoundary()` → `goToPreviousChapter()`.
- `TXTReaderViewModel.swift:456-459`: `nextChapter()` → `navigateToChapter(currentChapterIdx + 1)`; `previousChapter()` → `navigateToChapter(currentChapterIdx - 1)`.
- `TXTReaderViewModel.swift:363-401` (`navigateToChapter`): loads the chapter text, sets `currentChapterIdx`, `currentChapterText`, `textContent`, and `currentChapterLocalUTF16 = 0` ("Start at top of new chapter"). It updates `currentOffsetUTF16` and calls `broadcastPosition`. **It does NOT push any scroll command to the bridge** — no `scrollToOffset` write, no notification.
- `TXTTextViewBridge.swift:90-123` (`makeUIView`): scroll restore from `restoreOffset` is explicitly one-shot — "never re-applied". `updateUIView` (lines 128-227) only scrolls via the `scrollToOffset` path, gated by `shouldScroll(...)`. After a boundary-triggered chapter nav, `scrollToOffset` is `nil` (only search-tap / scrubber populate it via `uiState.scrollToOffset`).
- Conclusion: on a chapter swap, the new chapter's text is applied while the `UITextView` retains the prior chapter's `contentOffset.y`. If that was near `maxOffset` (bottom boundary — exactly the scroll position that triggered the nav), the new chapter renders scrolled to its end, AND the stale offset re-satisfies the bottom-boundary predicate on the next settle → `goToNextChapter()` re-fires → cascading multi-chapter skip. `isChapterNavInFlight` (`TXTReaderViewModel.swift:125, 364-368`) only blocks overlapping `loadChapter` awaits; it does not prevent a fresh settled scroll from re-triggering the boundary.

This is a genuine regression of the #180 fix — the original symptom (scroll bounces, no advance) was a missing capability; the new symptom (cascading wrong-position jumps) was introduced by the fix. Per the triage rules, a fixed bug that re-breaks is REOPENED, not a new bug.

- Severity unchanged at Medium — scroll mode is usable via the chrome button still, but boundary scrolling is now actively wrong.
- Status flip `FIXED`/`TODO` → `REOPENED`. Note: the summary-table row had never been flipped to `FIXED` after PR #681 (a tracker-hygiene slip — detail header said FIXED, summary row said TODO); both are now `REOPENED`. The `check_terminal_status_evidence.sh` hook does not gate `REOPENED`.

## Verdict

ship-as-is — documentation only, no code risk. The fix itself will follow on its own PR (`/fix-issue 614`).
