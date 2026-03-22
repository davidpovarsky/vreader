#  Feature Tracker

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

| #  | Summary                                                       | Area          | Priority | Status    | Notes                                                                                                                                                                            |
| -- | ------------------------------------------------------------- | ------------- | -------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1  | Edit and delete bookmarks                                     | Reader/*     | High     | DONE      | Rename via context menu (bug #42), delete via swipe + context menu. BookmarkListView has full CRUD UI                                                                            |
| 2  | Highlight search result at destination                        | Search/*     | Medium   | DONE      | Resolved by bug #43 — yellow background highlight, auto-clears after 3s                                                                                                          |
| 3  | Manual text highlighting                                      | Reader/*     | High     | DONE      | Resolved by bug #44 — Highlight action added to UITextView edit menu                                                                                                             |
| 4  | Add notes/annotations to text                                 | Reader/*     | Medium   | DONE      | Resolved by bug #44 — Add Note action added to UITextView edit menu                                                                                                              |
| 5  | Search highlight auto-dismiss on next action                  | Search/*     | Low      | TODO      | WI-003 code committed. Unchecked on device                                                                                                                                       |
| 6  | Persist library view preferences across app restarts          | Library/*    | Medium   | DONE      | WI-001. PreferenceStore + UserDefaults. 10 tests                                                                                                                                 |
| 7  | Visual feedback when adding a bookmark                        | Reader/*     | Low      | DONE      | WI-002. UIImpactFeedbackGenerator(.light). 5 tests                                                                                                                               |
| 8  | Reading position scrubber/progress bar                        | Reader/*     | Medium   | DONE      | WI-004a-d. ReadingProgressBar + per-format wiring (TXT/MD/PDF/EPUB). 108 tests                                                                                                   |
| 9  | Comprehensive book context menu in library                    | Library/*    | Medium   | DONE      | WI-006. Info/Share/Delete + BookInfoSheet. 24 tests                                                                                                                              |
| 10 | iCloud backup and restore                                     | Settings/*   | Medium   | TODO      | WI-E02. CloudKit for metadata, iCloud Drive for books. Shares BackupProvider with #29. Design doc at docs/codex-plans/icloud-backup-design.md                                    |
| 11 | EPUB text highlighting and note-taking                        | EPUB/*       | High     | TODO      | WI-C00 → WI-007 code committed. User: highlight dialog not appearing (bug #77)                                                                                                   |
| 12 | Auto-generate TOC for MD files                                | Reader/*     | Medium   | DONE      | WI-005. Regex heading extraction, fenced code block skip, correct UTF-16 offsets. 25 tests                                                                                       |
| 13 | AI book/chapter summarization                                 | AI/*         | High     | DONE      | WI-D00 → WI-009 → WI-010. Bug #92 FIXED (encoding). Device verified: non-UTF-8 TXT → AI summarize shows real content                                                            |
| 14 | AI chat — talk to the book                                    | AI/*         | High     | DONE      | WI-D00 → WI-009 → WI-010 → WI-011. Multi-turn chat with book context via AIChatViewModel. Chat tab in AIReaderPanel                                                              |
| 15 | AI chat interface (general)                                   | AI/*         | Medium   | DONE      | WI-013. General chat (nil bookFingerprint). Entry point in LibraryView toolbar. 8 tests                                                                                          |
| 16 | Remote server integration (claude CLI / directory management) | Server/*     | High     | DEFERRED  | WI-014 (design only). Design doc at docs/codex-plans/remote-server-design.md                                                                                                     |
| 17 | PDF text highlighting, annotation, and theming                | PDF/*        | High     | DONE      | WI-C00 → WI-008. PDFAnnotationBridge + selection detection + persist/restore. 44 tests                                                                                           |
| 18 | AI-powered contextual translation with bilingual view         | AI/*         | High     | DONE      | WI-012. Bug #95 FIXED (initialTab). Device verified: Select word → Translate → opens Translate tab                                                                                |
| 19 | ~~Merged into feature #6~~                                    | Library/*    | —        | DUPLICATE | Display mode persistence merged into feature #6 (library view preferences)                                                                                                       |
| 20 | Sort order reset/revert to default                            | Library/*    | Low      | DONE      | WI-001 (bundled with #6). "Default" option in sort picker                                                                                                                        |
| 21 | Paginated reading mode with turnable pages                    | Reader/*     | High     | TODO      | B04-B13 code committed. User: still scrolls (bug #82)                                                                                                                            |
| 22 | Highlight matching text in search result list                 | Search/*     | Medium   | DONE      | Bold/highlight query term in search result row snippets                                                                                                                          |
| 23 | Auto-generate TOC for TXT files                               | Reader/*     | Medium   | TODO      | B01 code committed. User: not matching files (bug #83)                                                                                                                           |
| 24 | Book source scraping (web novels)                             | BookSource/* | High     | DONE      | D01-D07. Bugs #100, #101 FIXED (modelContext.save + SchemaV4). Device verified: Import JSON → sources visible → search works                                                     |
| 25 | Configurable tap zones                                        | Reader/*     | High     | TODO      | A03. TapZoneStore + TapZoneConfig infrastructure exists but NO settings UI to configure zone actions                                                                             |
| 26 | Text-to-Speech read aloud                                     | Reader/*     | High     | TODO      | B03+E06 code committed. User: no sound, no error indication (bug #96). TTS bar overlaps bottom (bug #97)                                                                        |
| 27 | Content replacement rules                                     | Reader/*     | Low      | TODO      | E03 code committed. User: transforms fail (bug #98)                                                                                                                              |
| 28 | Simplified/Traditional Chinese conversion                     | Reader/*     | Medium   | TODO      | E04 code committed. User: transforms fail (bug #98)                                                                                                                              |
| 29 | WebDAV backup and restore                                     | Settings/*   | Medium   | TODO      | E01 code committed. Not verified on device                                                                                                                                       |
| 30 | Custom book covers                                            | Library/*    | Medium   | DONE      | A01. CustomCoverStore + PhotosPicker in context menu                                                                                                                             |
| 31 | Auto page turning                                             | Reader/*     | Low      | TODO      | B10 code committed. Blocked by paged mode not working (bug #82)                                                                                                                  |
| 32 | Reading theme backgrounds                                     | Reader/*     | Medium   | TODO      | A04. ThemeBackgroundView renders + opacity works, but NO image picker UI to select a background image                                                                            |
| 33 | Dictionary / define / translate-on-select                     | Reader/*     | High     | DONE      | B02. DictionaryLookup + UIReferenceLibraryViewController + AI translate                                                                                                          |
| 34 | Collections / tags / series organization                      | Library/*    | Medium   | TODO      | C01 code committed. User: can't add books to collections (bug #85), tags never shown (bug #86)                                                                                   |
| 35 | Export / import annotations                                   | Reader/*     | Medium   | TODO      | C02+C03 code committed. Not verified on device                                                                                                                                   |
| 36 | OPDS catalog support                                          | BookSource/* | Medium   | TODO      | C04 code committed. Not verified on device                                                                                                                                       |
| 37 | Per-book reading settings                                     | Reader/*     | Low      | TODO      | A05. Toggle + JSON save exists but resolve() never called at runtime. ReaderSettingsStore always uses global UserDefaults                                                        |
| 38 | Hierarchical/tree TOC display                                 | Reader/*     | Low      | DONE      | TOCListView indents by entry.level. PDF/MD builders populate nonzero levels. Not a disclosure tree but visual nesting works                                                      |
| 39 | ~~Merged into feature #32~~                                   | Reader/*     | —        | DUPLICATE | Same gap: background image picker UI needed. Merged into #32                                                                                                                     |
| 40 | TTS sentence highlighting                                     | Reader/*     | Medium   | TODO      | Highlight current sentence/word while TTS reads aloud. Requires AVSpeechSynthesizerDelegate range tracking                                                                       |
| 41 | TTS auto-scroll/paginate                                      | Reader/*     | Medium   | TODO      | Auto-scroll content to follow TTS reading position. Depends on #40 for position tracking                                                                                        |

