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
| 10 | iCloud backup and restore                                     | Settings/*   | —        | WONT DO   | Not needed. WebDAV (#29) covers backup needs.                                                                                                                                    |
| 11 | EPUB text highlighting and note-taking                        | EPUB/*       | High     | DONE      | WI-C00 → WI-007. Bug #77 FIXED (JS buffering). Needs device verification                                                                                                         |
| 12 | Auto-generate TOC for MD files                                | Reader/*     | Medium   | DONE      | WI-005. Regex heading extraction, fenced code block skip, correct UTF-16 offsets. 25 tests                                                                                       |
| 13 | AI book/chapter summarization                                 | AI/*         | High     | DONE      | WI-D00 → WI-009 → WI-010. Bug #92 FIXED (encoding). Device verified: non-UTF-8 TXT → AI summarize shows real content                                                            |
| 14 | AI chat — talk to the book                                    | AI/*         | High     | DONE      | WI-D00 → WI-009 → WI-010 → WI-011. Multi-turn chat with book context via AIChatViewModel. Chat tab in AIReaderPanel                                                              |
| 15 | AI chat interface (general)                                   | AI/*         | Medium   | DONE      | WI-013. General chat (nil bookFingerprint). Entry point in LibraryView toolbar. 8 tests                                                                                          |
| 16 | Remote server integration (claude CLI / directory management) | Server/*     | High     | DEFERRED  | WI-014 (design only). Design doc at docs/codex-plans/remote-server-design.md                                                                                                     |
| 17 | PDF text highlighting, annotation, and theming                | PDF/*        | High     | DONE      | WI-C00 → WI-008. PDFAnnotationBridge + selection detection + persist/restore. 44 tests                                                                                           |
| 18 | AI-powered contextual translation with bilingual view         | AI/*         | High     | DONE      | WI-012. Bug #95 FIXED (initialTab). Device verified: Select word → Translate → opens Translate tab                                                                                |
| 19 | ~~Merged into feature #6~~                                    | Library/*    | —        | DUPLICATE | Display mode persistence merged into feature #6 (library view preferences)                                                                                                       |
| 20 | Sort order reset/revert to default                            | Library/*    | Low      | DONE      | WI-001 (bundled with #6). "Default" option in sort picker                                                                                                                        |
| 21 | Paginated reading mode with turnable pages                    | Reader/*     | High     | DONE      | B04-B13. Bug #82 FIXED (preserve navigator). Needs device verification                                                                                                           |
| 22 | Highlight matching text in search result list                 | Search/*     | Medium   | DONE      | Bold/highlight query term in search result row snippets                                                                                                                          |
| 23 | Auto-generate TOC for TXT files                               | Reader/*     | Medium   | DONE      | B01. Bug #83 FIXED (14/25 rules enabled). Needs device verification                                                                                                              |
| 24 | Book source scraping (web novels)                             | BookSource/* | High     | DONE      | D01-D07. Bugs #100, #101 FIXED (modelContext.save + SchemaV4). Device verified: Import JSON → sources visible → search works                                                     |
| 25 | Configurable tap zones                                        | Reader/*     | High     | DONE      | A03. TapZone section in ReaderSettingsPanel — 3 Pickers (left/center/right → TapAction). TapZoneStore wired through settings sheet                                               |
| 26 | Text-to-Speech read aloud                                     | Reader/*     | High     | DONE      | B03+E06. Bugs #96, #97 FIXED. Needs device verification                                                                                                                          |
| 27 | Content replacement rules                                     | Reader/*     | Low      | DONE      | E03. Bug #98 FIXED (sourceText + didSet re-apply). Needs device verification                                                                                                     |
| 28 | Simplified/Traditional Chinese conversion                     | Reader/*     | Medium   | DONE      | E04. Bug #98 FIXED (sourceText + didSet re-apply). Needs device verification                                                                                                     |
| 29 | WebDAV backup and restore                                     | Settings/*   | Medium   | TODO      | E01 code committed. Not verified on device                                                                                                                                       |
| 30 | Custom book covers                                            | Library/*    | Medium   | DONE      | A01. CustomCoverStore + PhotosPicker in context menu                                                                                                                             |
| 31 | Auto page turning                                             | Reader/*     | Low      | DONE      | B10. Unblocked by bug #82 fix. Needs device verification                                                                                                                         |
| 32 | Reading theme backgrounds                                     | Reader/*     | Medium   | DONE      | A04. PhotosPicker + opacity slider + remove button in ReaderSettingsPanel. ThemeBackgroundStore saves/loads per-theme. Needs device verification                                  |
| 33 | Dictionary / define / translate-on-select                     | Reader/*     | High     | DONE      | B02. DictionaryLookup + UIReferenceLibraryViewController + AI translate                                                                                                          |
| 34 | Collections / tags / series organization                      | Library/*    | Medium   | DONE      | C01. Bugs #85, #86 FIXED. Needs device verification                                                                                                                              |
| 35 | Export / import annotations                                   | Reader/*     | Medium   | DONE      | C02+C03. Bug #88 FIXED (import highlight refresh). Needs device verification                                                                                                     |
| 36 | OPDS catalog support                                          | BookSource/* | Medium   | TODO      | C04 code committed. Not verified on device                                                                                                                                       |
| 37 | Per-book reading settings                                     | Reader/*     | Low      | DONE      | A05. Bug #84 FIXED (applyResolvedSettings + suppressPersistence). Needs device verification                                                                                      |
| 38 | Hierarchical/tree TOC display                                 | Reader/*     | Low      | DONE      | TOCListView indents by entry.level. PDF/MD builders populate nonzero levels. Not a disclosure tree but visual nesting works                                                      |
| 39 | ~~Merged into feature #32~~                                   | Reader/*     | —        | DUPLICATE | Same gap: background image picker UI needed. Merged into #32                                                                                                                     |
| 40 | TTS sentence highlighting                                     | Reader/*     | Medium   | DONE      | TTSHighlightCoordinator: NLTokenizer sentences → binary search → uiState.highlightRange. TXT/MD wired via onChange(ttsService). Needs device verification                        |
| 41 | TTS auto-scroll/paginate                                      | Reader/*     | Medium   | DONE      | TTSHighlightCoordinator sets uiState.scrollToOffset from sentence start. TXT/MD only via same onChange wiring. Needs device verification                                         |
| 42 | AZW3/KF8 + Foliate-js unified reader engine                   | Reader/*     | High     | PLANNED   | Replace EPUB bridge with Foliate-js `<foliate-view>`. EPUB+AZW3/MOBI via one engine. PDF/TXT unchanged. GH: #113                                                                |
| 43 | Extract and display cover images from EPUB/AZW3               | Library/*    | Medium   | DONE      | EPUB OPF + AZW3 MOBI header parsing. 46 tests. Bug #107 for white-edge padding. GH: #121                                                                                        |
| 44 | DebugBridge — debug-only URL scheme + state dumper for autonomous testing | DevTools/*  | High | PLANNED | DEBUG-only `vreader-debug://` handler. Enables AI-driven repro/debug loop and XCUITest state setup. ~200 LOC, no release surface. See plan below. |

### Feature #44 — DebugBridge — Plan

- **Problem**: Autonomous AI debug loop and XCUITest regression suite both need cheap, deterministic state setup and ground-truth state inspection. Currently every repro requires manual UI-driving (open library → tap book → scroll → set theme → ...). For WKWebView-heavy bugs (Foliate-js highlights, EPUB rendering, page navigation) there is no external way to read what the webview actually rendered. Vision-only inspection is too flaky for the hard bugs, which is the class that piles up in `docs/bugs.md`.

- **Scope**:
  - **Included**: A `#if DEBUG`-gated `DebugBridge` that handles the `vreader-debug://` URL scheme via `.onOpenURL` on `VReaderApp`. Commands: `reset`, `seed?fixture=<name>`, `open?bookId=<uuid>&cfi=<x>` (plus equivalent for TXT/MD/PDF positions), `theme?mode=<dark|light>&fontSize=<n>`, `settle?token=<id>` (writes ready-sentinel after Foliate `relocate` + native layout settles), `snapshot?dest=<file>` (semantic state JSON to app container), `eval?bridge=foliate&js=<base64>` (active WKWebView JS eval, result to container). Bundle a small set of fixture books in `vreader/Resources/DebugFixtures/` (alice.epub, war-and-peace.txt, sample.azw3, sample.pdf). Document one repro recipe per existing open bug (#107, #108, plus a few of the "Needs device verification" features) in `dev-docs/debug-bridge.md`.
  - **Excluded**: No release-build code path. No remote control over network. No authentication (device-local only, DEBUG-only). No fixture *editing* in the bridge — fixtures are read-only bundle resources. No replacement of XCUITest — DebugBridge is a state-setup peer, not a test runner. No screenshot capture from inside the bridge — caller uses `xcrun simctl io booted screenshot`. No mutation of SwiftData beyond the `reset` and `seed` commands.
  - **Out of scope, deferred**: Recording-and-replay of user gestures. Mocking the network layer. AI Genie state injection.

- **Edge cases**:
  - URL scheme called in non-DEBUG build → ignore silently (handler not registered).
  - `seed` called twice with the same fixture → idempotent (no duplicate library row).
  - `open` with unknown `bookId` → write error JSON to `lastError.json`, do not crash.
  - `eval` JS that throws → capture exception in result JSON; do not propagate to app.
  - `eval` called when no webview is active → return `{ "error": "no active webview" }`.
  - `settle` called when render never completes (e.g., corrupt EPUB) → timeout sentinel after 30s with `{ "error": "settle timeout", "phase": "<lastPhase>" }`.
  - Concurrent `vreader-debug://` calls → serialize via `MainActor` queue; later calls wait.
  - Snapshot during in-flight TTS or AI streaming → state JSON includes a `transientOps` array so caller can decide whether to retry.
  - Filesystem write failures on `Caches/` → log and continue; do not block app.
  - `reset` while a book is open → close reader first, dismiss sheets, then wipe.
  - Build configuration with `DEBUG` undefined but URL scheme registered (e.g., archive build): URL scheme registration also `#if DEBUG`-gated in Info.plist via Active Compilation Conditions check at build phase. Verify no `vreader-debug` entry leaks into Release.app.
  - `snapshot` JSON must exclude PII (no fingerprinting hashes of book content beyond what's already in SwiftData).

- **Test plan**:
  - Unit: `DebugBridgeRouterTests` — URL parsing for each command, error paths (malformed URL, missing required params, unknown command).
  - Unit: `DebugStateSnapshotterTests` — JSON shape stability against a fixed model (golden JSON), nil/optional handling, `transientOps` array population.
  - Unit: `DebugFixtureLoaderTests` — idempotent `seed`, missing fixture name → error, fixture path resolution.
  - Integration: `DebugBridgeIntegrationTests` (XCUITest) — launch with `vreader-debug://reset` then `seed` then `open` then `snapshot`, read back container JSON, assert state matches expected.
  - Integration: `DebugBridgeFoliateEvalTests` — open EPUB fixture, `eval` returns `document.querySelectorAll('.foliate-highlight').length` correctly after creating a highlight.
  - Build gate: a CI step asserts `vreader-debug` is **not** present in the Release bundle's Info.plist. Fail the build if found.
  - Manual verification: one repro recipe in `dev-docs/debug-bridge.md` exercised end-to-end against current open bugs.

- **Acceptance criteria**:
  - DEBUG build registers `vreader-debug://` and handles all six commands above with correct success/error JSON in the app container.
  - Release build has zero `vreader-debug` references (verified by CI grep + Info.plist check).
  - `xcrun simctl openurl booted vreader-debug://snapshot?dest=state.json` followed by `simctl get_app_container booted <bundle-id> data` produces a valid JSON file with the documented schema (currentBookId, format, cfi/page, theme, fontSize, selection, highlightCount, renderPhase, lastError).
  - `settle` reliably blocks until the Foliate `relocate` event has fired and a frame has been committed (no mid-frame screenshots in the documented happy-path repro).
  - All unit + integration tests pass under `xcodebuild test -only-testing:vreaderTests` and `-only-testing:vreaderUITests`.
  - `dev-docs/debug-bridge.md` documents the URL grammar, JSON schema, fixture catalogue, and one worked repro per currently-open bug.
  - LOC under ~300 across new files (router, snapshotter, fixture loader, Foliate eval adapter); no file exceeds the project's 300-line guideline.

