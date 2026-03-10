# Feature Tracker

Track features to be implemented here. Must be planned before implementation.

## Rules

- **Bugs vs features**: If something was implemented but doesn't work correctly, it is a **bug** — track it in `docs/bugs.md`. If something was never implemented, it is a **feature** — track it here. Never mix them.
- **Partial implementations**: If something is partially implemented, the broken part is a bug in `docs/bugs.md`; the missing capability is a feature here. Link them.
- **Cross-links**: When a bug fix resolves a feature, update the feature status to `DONE` with note `Resolved by bug #N`. When a feature depends on a bug fix, use `TODO` status with note `Blocked by bug #N`.
- **Plan before implementation**: Every feature must be planned before any code is written. Status must reach `PLANNED` before moving to `IN PROGRESS`. A plan requires the fields listed in the "Plan Template" section below.
- **Exception — resolved by bug fix**: If a bug fix incidentally delivers a feature, the feature may be set to `DONE` with `Resolved by bug #N` without a full plan. The bug's own cause/solution/lesson records serve as documentation.

## How to use

1. Add features as you identify them (fill in Summary and Area at minimum)
2. Plan the feature (fill in required plan fields above) → set status to `PLANNED`
3. Tell the agent: "implement feature #N" to start implementation
4. Agent updates Status when done

- **GitHub Issue closure** (post-merge finalizer — see `AGENTS.md` for full policy):
  - If the feature has a `GH: #N` in Notes, close the GitHub Issue only after:
    1. All acceptance criteria met and status is DONE in this file.
    2. Implementation is merged to `main`.
    3. Closure comment posted with commit SHA and acceptance result.
  - Partial delivery: keep GitHub Issue open; use checklist or split follow-ups.
  - PRs use `Refs #N`, not `Fixes #N` (prevents premature auto-close).

## Statuses

- `TODO` — not started
- `PLANNED` — plan complete (problem, scope, edge cases, tests, acceptance criteria), ready to implement
- `IN PROGRESS` — being worked on
- `DONE` — implemented and verified
- `DEFERRED` — postponed to a later milestone
- `WONT DO` — out of scope or rejected

## Plan Template

Before setting a feature to `PLANNED`, fill in these fields in a sub-section under the feature table (e.g., `### Feature #1 — Plan`):

- **Problem**: What user need does this address?
- **Scope**: What is included and excluded?
- **Edge cases**: Empty input, nil, boundary values, concurrent access, format-specific behavior.
- **Test plan**: What tests will verify the feature?
- **Acceptance criteria**: How do we know it's done?

## Features

| #  | Summary | Area | Priority | Status | Notes |
| -- | ------- | ---- | -------- | ------ | ----- |
| 1  | Edit and delete bookmarks | Reader/* | High | TODO | Bookmark creation exists (bug #31). Rename added (bug #42). Full edit/delete UI not implemented |
| 2  | Highlight search result at destination | Search/* | Medium | DONE | Resolved by bug #43 — yellow background highlight, auto-clears after 3s |
| 3  | Manual text highlighting | Reader/* | High | DONE | Resolved by bug #44 — Highlight action added to UITextView edit menu |
| 4  | Add notes/annotations to text | Reader/* | Medium | DONE | Resolved by bug #44 — Add Note action added to UITextView edit menu |
| 5  | Search highlight auto-dismiss on next action | Search/* | Low | TODO | From task inbox — highlighted search result should clear when user performs another action (scroll, tap, new search) |
| 6  | Persist sort preference across app restarts | Library/* | Medium | TODO | sortOrder defaults to .title every launch; user selection not saved to UserDefaults/AppStorage |
| 7  | Visual feedback when adding a bookmark | Reader/* | Low | TODO | No toast, haptic, or icon change when bookmark button is tapped; user can't tell if it worked |
| 8  | Reading position scrubber/progress bar | Reader/* | Medium | TODO | No slider or progress bar to seek to arbitrary positions in large books; only scroll or search navigation |
| 9  | Comprehensive book context menu in library | Library/* | Medium | TODO | Context menu only has "Delete"; needs info/details, share, rename, and other management actions |
| 10 | iCloud backup and restore | Settings/* | Medium | TODO | No mechanism to backup library data (books, annotations, reading progress) to iCloud or restore from it |
| 11 | EPUB text highlighting and note-taking | EPUB/* | High | TODO | Only TXT/MD have edit menu for highlight/notes (UITextView). EPUB uses WKWebView — needs JS-based selection handling |
