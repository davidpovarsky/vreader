---
branch: triage/bug-179-reopened-di-restore-and-chapter-nav
bug: 179
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: reopens Bug #179 in `docs/bugs.md` and on GitHub (GH #611) after the user reported the original fix's scope was incomplete. The original fix (v3.21.31, commit 306e54f) added `safeAreaTopInset` to `TXTTextViewBridge` / `TXTChunkedReaderBridge` and applied it via `textContainerInset.top` — this correctly clears the DI on first-open at offset 0. Two paths remain broken:

1. Reopening the TXT file with saved reading position > 0
2. Navigating to a new chapter (chapter or scroll mode)

No Swift source changes. No test changes.

## Audit

No logic to audit. The reopen entry is grounded in code-read evidence:

- `TXTTextViewBridgeCoordinator.swift:104-122`: `attemptScrollRestore(in:toCharOffset:)` computes `scrollY = TXTOffsetMapper.charOffsetToScrollOffset(charOffset:layoutManager:textContainer:)` and calls `textView.setContentOffset(CGPoint(x: 0, y: scrollY), animated: false)` without subtracting `textView.textContainerInset.top`.
- `TXTTextViewBridgeCoordinator.swift:137-160`: sibling `scrollToMatchedOffset` computes the same `lineY` then routes through `TXTOffsetMapper.scrollOffsetForVisibleMatch(lineY:viewportHeight:topInset:)` — which DOES account for `textContainerInset.top`. That's why search-tap nav works.
- The original fix (`vreader/Views/Reader/TXTTextViewBridge.swift:39-65, 175-189`) only modified the static `textContainerInset` value, not the dynamic scroll-restore math. The two paths the user reports both route through `attemptScrollRestore` (file-reopen via the `restoreOffset > 0` branch at `TXTTextViewBridge.swift:95-119`; chapter-mode chapter-nav re-render also lands here for the new chapter's saved-or-zero offset).
- `MDReaderContainerView` shares `TXTTextViewBridge` for scroll mode — same regression scope likely. Native paged MD (`NativeTextPagedView`) was explicitly OUT OF SCOPE in the original fix; reassess in the re-fix.
- Severity unchanged at Medium — same symptom class as the original.

## Verdict

ship-as-is — documentation only, no code risk. Status flip from `FIXED` → `REOPENED` is not a terminal-state flip (`check_terminal_status_evidence.sh` only gates `FIXED` on `docs/features.md` for features and is documented as NOT enforcing bug `FIXED` flips, so `REOPENED` is unaffected). The fix work itself will follow on its own PR via `/fix-issue 611` (or equivalent).
