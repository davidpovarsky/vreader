# Task Inbox

Describe issues in plain text below. The agent will triage them.

## Rules

- **This file is an inbox, not a tracker.** Items stay here only until triaged.
- **User writes free-form descriptions** under the "New" section. No table, no formatting required.
- **Triage is classification only — not execution.** The agent does NOT fix bugs or implement features during triage. It only classifies and records.
- **Classification rules**:
  - Implemented but doesn't work correctly → **bug** → record in `docs/bugs.md`.
  - Never implemented → **feature** → record in `docs/features.md`.
  - Partially implemented + incorrect behavior → **bug** for the broken part; split off a separate **feature** for the missing capability. Link them.
  - Not a bug or feature (docs, config, chores, environment) → mark as `NO-ACTION` with reason.
  - Invalid or unclear → mark as `NEEDS-INFO` and ask the user.
- **Deduplication**: Before creating a new entry, search existing bugs and features. If a match exists:
  - Exact duplicate of an **open** bug (TODO/IN PROGRESS/REOPENED) → mark as `DUPLICATE OF bug #N` or `feature #N`.
  - Matches a **FIXED** bug → it's a regression, not a duplicate → mark as `REOPENED bug #N` and set that bug's status back to `REOPENED` in `docs/bugs.md`.
- **Agent workflow**: For each new item, the agent will:
  1. Read the description and investigate the codebase.
  2. Search `docs/bugs.md` and `docs/features.md` for existing matches.
  3. Classify per the rules above.
  4. Record based on classification:
     - **New bug/feature** → assign next available ID in the appropriate file. For bugs, also add an entry to `## Open Bug Details` in `docs/bugs.md` with the user's description (max 6 lines: repro, expected, actual).
     - **DUPLICATE** → no new ID; reference existing `bug #N` or `feature #N`.
     - **REOPENED** → no new ID; set existing bug's status to `REOPENED` in `docs/bugs.md`. Add/update `## Open Bug Details` entry with the new context.
     - **NO-ACTION / NEEDS-INFO** → no tracker entry; record only here.
  5. Move the description from "New" to "Triaged" with a one-line record:
     `YYYY-MM-DD | <bug #N / feature #N / DUPLICATE OF #N / REOPENED #N / NO-ACTION / NEEDS-INFO> | <reason>`
  6. If the result is **NO-ACTION** or **NEEDS-INFO**, prefix the line with `> ` (blockquote) so it stands out from resolved items.
  7. If the item is high-severity bug, release blocker, or major feature → also create a GitHub Issue (`gh issue create`) with appropriate labels. Add `GH: #123` to the tracker's Notes column.
- **NEEDS-INFO lifecycle**: If the user does not clarify within 7 days, the agent marks it `NO-ACTION (stale)` and moves on.
- **Never delete user content from New without explicit permission.** Items in New belong to the user. If an item matches an existing triage record, it is a re-report — the fix didn't work. REOPEN the bug and preserve the new information (crash logs, file paths, repro details). Do not treat re-reports as stale leftovers to clean up.

## New

<!-- Write issues here in plain text. One issue per line or paragraph. -->

## Triaged

2026-03-10 | feature #17 + DUPLICATE OF features #11, #13, #14 | EPUB/PDF text-like display — EPUB: highlighting/notes = feature #11 (TODO), theme/font = already works (bug #9), search = works, AI = features #13/#14 (TODO). PDF: highlighting/notes/theming = NEW feature #17 (PDFKit is read-only). Search = works
2026-03-10 | feature #18 | AI-powered contextual translation with bilingual view — never implemented. AIService.translate() exists but not wired. Needs translation UI, bilingual layout, toggle switch, API integration (claude -p or DeepL)
2026-03-10 | DUPLICATE OF feature #6 (expanded) | Library view persistence — sort order + display mode (grid/list) both covered by feature #6 (updated to include both)
2026-03-10 | feature #20 | Sort order reset/revert — never implemented. No reset option in sort picker menu

2026-03-10 | feature #12 | Auto-generate TOC for TXT/MD — TOCBuilder exists but forTXT()/forMD() return empty. Need heading extraction (MD) and heuristic chapter detection (TXT)
2026-03-10 | feature #13 | AI book/chapter summarization — full AIService pipeline exists and is functional but not wired to reader UI. Feature flag OFF
2026-03-10 | feature #14 | AI chat — talk to the book — single-question askQuestion() works. Missing multi-turn chat UI (message list, input field, history)
2026-03-10 | feature #15 | AI chat interface — general AI chat beyond book context. Overlaps with #14 but broader scope
2026-03-10 | feature #16 | Remote server integration (claude CLI) — no remote server code exists. Needs protocol design, networking, auth, UI
2026-03-10 | REOPENED bug #47 → FIXED v12 | Crash at frame #6 in setHighlightedText (textStorage.setAttributedString still crashes with active selection). Fixed: HighlightingLayoutManager.drawBackground() — zero text storage mutation for highlights. Applied to both TXTTextViewBridge and TXTChunkedReaderBridge.
2026-03-10 | REOPENED bug #47 → FIXED v11 | Crash at frame #45 in setHighlightedText (attributedText setter UIKit accessibility traversal with active selection). Fixed: textStorage.setAttributedString() + clear selection + isReplacingText guard. Audit applied: content-based persisted highlight comparison, removed unsafe attributedText fallback branches.
2026-03-10 | REOPENED bug #45 | "Last Read" sort resets on refresh/restart, only tracks last-opened book — v4 in-memory fix doesn't survive loadBooks(). Details updated in Open Bug Details in bugs.md
2026-03-10 | REOPENED bug #47 | Crash on highlight in test魔头.txt persists after v3 DispatchQueue.main.async fix. Details updated in Open Bug Details in bugs.md
2026-03-10 | bug #55 | Highlights not visible when file is reopened — no code to load persisted AnnotationRecords on file open. Details added to Open Bug Details in bugs.md
2026-03-09 | REOPENED bug #45 | "Last Read" sort still stale after v3 in-memory fix — user re-reports with 3 test files. Details moved to Open Bug Details in bugs.md
2026-03-09 | REOPENED bug #47 | Crash persists when highlighting in test魔头.txt — _os_unfair_lock_unowned_abort crash log preserved in Open Bug Details in bugs.md
2026-03-09 | REOPENED bug #54 | Highlights still disappear in large CJK TXT after a few seconds — details moved to Open Bug Details in bugs.md
2026-03-09 | REOPENED bug #47 | App crashes when highlighting in test魔头.txt — user reports crash persists after previous fix
2026-03-09 | REOPENED bug #45 | Library sorting by "Last Read" still does not work — user reports issue persists after v2 event-driven fix
2026-03-09 | bug #54 | Highlight disappears in large CJK TXT after selecting other text — chunked reader cell reuse wipes highlight attributes + no persistent rendering
2026-03-08 | DUPLICATE OF bug #45 (FIXED) | "Last Read" sort — already fixed; stats recomputed on reader close + .onAppear refresh
2026-03-08 | feature #5 | Search highlight auto-dismiss — new behavior, never implemented
2026-03-08 | bug #46 | Manual highlight saves record but content not highlighted — implemented but broken
2026-03-09 | REOPENED bug #45 | Library still doesn't refresh sort after closing book — .onAppear fix insufficient
2026-03-09 | feature #6 | Sort preference persistence — never implemented, defaults to .title on every launch
2026-03-09 | bug #47 | App crashes after search/bookmark navigation + tap — implemented but crashes
2026-03-09 | bug #48 | Highlight/note edit menu missing in large TXT files — chunked reader lacks editMenuForTextIn
2026-03-09 | bug #49 | Note input box too narrow — TextField used instead of TextEditor
2026-03-09 | bug #50 | Highlight/annotation navigation fails — LocatorFactory.txtRange doesn't set charOffsetUTF16
2026-03-09 | bug #51 | Notes don't show original annotated text — AnnotationRecord missing selectedText field
2026-03-09 | bug #47 | App crashes on bookmark + double tap — same root cause as item 3 (merged into bug #47)
2026-03-09 | feature #7 | No visual feedback when adding bookmark — never implemented
2026-03-09 | feature #8 | Reading position scrubber/progress bar for large books — never implemented
2026-03-09 | feature #9 | Comprehensive book context menu — only "Delete" exists, needs info/share/rename
2026-03-09 | feature #10 | iCloud backup and restore — never implemented
2026-03-09 | REOPENED bug #45 | "Last Read" sort still stale after closing book — force refresh + 300ms delay still not working
2026-03-09 | DUPLICATE OF bug #47 (FIXED) | App crashed when highlighting TXT — same applyHighlight integer underflow crash path
2026-03-09 | feature #11 | EPUB cannot highlight text or add notes — never implemented for EPUB (WKWebView needs JS-based approach)
2026-03-09 | bug #52 | Large CJK TXT annotation panel navigation fails — chunkedReaderContent() doesn't pass scrollToOffset to bridge
2026-03-09 | bug #53 | Highlight visual not applied in large CJK TXT — chunkedReaderContent() doesn't pass highlightRange to bridge
