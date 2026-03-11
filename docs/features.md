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
| 1  | Edit and delete bookmarks | Reader/* | High | DONE | Rename via context menu (bug #42), delete via swipe + context menu. BookmarkListView has full CRUD UI |
| 2  | Highlight search result at destination | Search/* | Medium | DONE | Resolved by bug #43 — yellow background highlight, auto-clears after 3s |
| 3  | Manual text highlighting | Reader/* | High | DONE | Resolved by bug #44 — Highlight action added to UITextView edit menu |
| 4  | Add notes/annotations to text | Reader/* | Medium | DONE | Resolved by bug #44 — Add Note action added to UITextView edit menu |
| 5  | Search highlight auto-dismiss on next action | Search/* | Low | PLANNED | WI-003. Clear highlight on scroll, tap, or new search |
| 6  | Persist library view preferences across app restarts | Library/* | Medium | PLANNED | WI-001. PreferenceStore wrapping UserDefaults for sortOrder + viewMode |
| 7  | Visual feedback when adding a bookmark | Reader/* | Low | PLANNED | WI-002. UIImpactFeedbackGenerator(.light) on successful toggle |
| 8  | Reading position scrubber/progress bar | Reader/* | Medium | PLANNED | WI-004. UISlider overlay at bottom of reader |
| 9  | Comprehensive book context menu in library | Library/* | Medium | PLANNED | WI-006. Add Info, Share alongside Delete |
| 10 | iCloud backup and restore | Settings/* | Medium | PLANNED | WI-015 (design only). Deferred to V2 |
| 11 | EPUB text highlighting and note-taking | EPUB/* | High | PLANNED | WI-C00 (anchor schema) → WI-007. JS injection for WKWebView selection |
| 12 | Auto-generate TOC for MD files | Reader/* | Medium | PLANNED | WI-005. MD heading extraction via regex (skip fenced code blocks). TXT deferred indefinitely — too fragile |
| 13 | AI book/chapter summarization | AI/* | High | PLANNED | WI-D00 (AI foundation) → WI-009 (settings) → WI-010. Wire AIAssistantViewModel to reader toolbar |
| 14 | AI chat — talk to the book | AI/* | High | PLANNED | WI-D00 → WI-009 → WI-010 → WI-011. Multi-turn chat with book context. Shares AIChatViewModel with #15 |
| 15 | AI chat interface (general) | AI/* | Medium | PLANNED | WI-D00 → WI-009 → WI-010 → WI-011 → WI-013. General chat (nil bookFingerprint). Separate entry point from library, shared ViewModel with #14 |
| 16 | Remote server integration (claude CLI / directory management) | Server/* | High | PLANNED | WI-014 (design only). Deferred to V2 |
| 17 | PDF text highlighting, annotation, and theming | PDF/* | High | PLANNED | WI-C00 (anchor schema) → WI-008. PDFAnnotation API for highlights |
| 18 | AI-powered contextual translation with bilingual view | AI/* | High | PLANNED | WI-D00 → WI-009 → WI-010 → WI-012. Bilingual side-by-side display |
| 19 | ~~Merged into feature #6~~ | Library/* | — | DUPLICATE | Display mode persistence merged into feature #6 (library view preferences) |
| 20 | Sort order reset/revert to default | Library/* | Low | PLANNED | WI-001 (bundled with #6). Add "Default" option in sort picker |
