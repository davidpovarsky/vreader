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
| 5  | Search highlight auto-dismiss on next action | Search/* | Low | DONE | WI-003. Clear on scroll, tap, or new search. Per-format ownership. 15 tests |
| 6  | Persist library view preferences across app restarts | Library/* | Medium | DONE | WI-001. PreferenceStore + UserDefaults. 10 tests |
| 7  | Visual feedback when adding a bookmark | Reader/* | Low | DONE | WI-002. UIImpactFeedbackGenerator(.light). 5 tests |
| 8  | Reading position scrubber/progress bar | Reader/* | Medium | DONE | WI-004a-d. ReadingProgressBar + per-format wiring (TXT/MD/PDF/EPUB). 108 tests |
| 9  | Comprehensive book context menu in library | Library/* | Medium | DONE | WI-006. Info/Share/Delete + BookInfoSheet. 24 tests |
| 10 | iCloud backup and restore | Settings/* | Medium | DEFERRED | WI-015 (design only). Design doc at docs/codex-plans/icloud-backup-design.md |
| 11 | EPUB text highlighting and note-taking | EPUB/* | High | DONE | WI-C00 → WI-007. CSS Highlight API + EPUBHighlightBridge + persist/restore. 37 tests |
| 12 | Auto-generate TOC for MD files | Reader/* | Medium | DONE | WI-005. Regex heading extraction, fenced code block skip, correct UTF-16 offsets. 25 tests |
| 13 | AI book/chapter summarization | AI/* | High | DONE | WI-D00 → WI-009 → WI-010. AIReaderPanel + toolbar button. 18 tests |
| 14 | AI chat — talk to the book | AI/* | High | DONE | WI-D00 → WI-009 → WI-010 → WI-011. Multi-turn chat with book context via AIChatViewModel. Chat tab in AIReaderPanel |
| 15 | AI chat interface (general) | AI/* | Medium | DONE | WI-013. General chat (nil bookFingerprint). Entry point in LibraryView toolbar. 8 tests |
| 16 | Remote server integration (claude CLI / directory management) | Server/* | High | DEFERRED | WI-014 (design only). Design doc at docs/codex-plans/remote-server-design.md |
| 17 | PDF text highlighting, annotation, and theming | PDF/* | High | DONE | WI-C00 → WI-008. PDFAnnotationBridge + selection detection + persist/restore. 44 tests |
| 18 | AI-powered contextual translation with bilingual view | AI/* | High | DONE | WI-D00 → WI-009 → WI-010 → WI-012. BilingualView + TranslationPanel. 14 tests |
| 19 | ~~Merged into feature #6~~ | Library/* | — | DUPLICATE | Display mode persistence merged into feature #6 (library view preferences) |
| 20 | Sort order reset/revert to default | Library/* | Low | DONE | WI-001 (bundled with #6). "Default" option in sort picker |
| 21 | Paginated reading mode with turnable pages | Reader/* | Medium | TODO | Scroll-only currently. User wants page-turn mode like iBooks |
| 22 | Highlight matching text in search result list | Search/* | Low | TODO | Result rows show plain text snippets. Should bold/highlight the matching query term |
