# Bug Tracker

Track bugs here. Tell the agent "fix bug #N" to start a fix.

## Rules

- **Bugs vs features**: If something was implemented but doesn't work correctly, it is a **bug** — track it here. If something was never implemented, it is a **feature** — track it in `docs/features.md`. Never mix them.
- **Partial implementations**: If something is partially implemented, the broken part is a bug here; the missing capability is a feature in `docs/features.md`. Link them.
- **Source of truth**: This **Summary table** is the single source of truth for bug status.
- **Open bug details**: Bugs with status TODO/IN PROGRESS/REOPENED should have an entry in `## Open Bug Details` with repro context. Move to archive on FIXED.
- **History**: Root causes, solutions, and lessons for FIXED bugs are archived in `docs/archive/bugs-history.md`.

## How to use

1. Add bugs as you find them (fill in Summary and File/Area at minimum)
2. Tell the agent: "fix bug #N" — it will follow the workflow below
3. Agent updates Status when done

- **Bug fix workflow** (follow this order for every bug):
  1. **Understand**: Read the file/area, reproduce the symptom, identify root cause (not just location). Run `/codex-toolkit:bug-analyze`. If it is not a bug, move it to `docs/features.md`.
  2. **RED**: Write a failing test that proves the bug exists.
  3. **GREEN**: Minimal fix to make the test pass.
  4. **REFACTOR**: Clean up without changing behavior.
  5. **Verify**: Run tests, confirm the fix, check for regressions. Run `/codex-toolkit:audit-fix` on changed files.
  6. **Track**: Update status in the Summary table to FIXED.
  7. Do NOT commit unless explicitly requested.
  8. Record cause, solution, and lessons in `docs/archive/bugs-history.md`. Remove the bug's entry from `## Open Bug Details`.
- **GitHub Issue closure** (post-merge finalizer — see `AGENTS.md` for full policy):
  - If the bug has a `GH: #N` in Notes, close the GitHub Issue only after:
    1. Status is FIXED in this file.
    2. Fix is merged to `main`.
    3. Closure comment posted with commit SHA, test evidence, and cause summary.
  - PRs use `Refs #N`, not `Fixes #N` (prevents premature auto-close).

## Statuses

- `TODO` — not started
- `IN PROGRESS` — being worked on
- `FIXED` — fix verified in working tree (not necessarily committed)
- `REOPENED` — previously fixed but regressed; link to original fix
- `DUPLICATE` — duplicate of another bug; note `DUPLICATE OF #N`
- `WONT FIX` — intentional behavior or out of scope

## Open Bug Detail

<!-- For each TODO/IN PROGRESS/REOPENED bug, add a short entry here.
     Max 6 lines per bug. Remove on FIXED (move to archive). -->

<!-- No open bugs -->

## Summary

| #  | Summary                                                                                               | File/Area  | Severity | Status   | Notes                                                                                                                                               |
| -- | ----------------------------------------------------------------------------------------------------- | ---------- | -------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1  | CJK search returns no results                                                                         | Search/*  | High     | FIXED    | FTS5 tokenization + encoding + race condition (0d48d0a)                                                                                             |
| 2  | The search results are incomplete; only a few results are shown.                                      | Search/*  | High     | FIXED    | FTS5 returned 1 hit per segment; now expands to all occurrences via span map                                                                        |
| 3  | Progress cannot be saved. Each time the TXT file is opened, it starts from the beginning.             | Reader/*  | High     | FIXED    | TXTTextViewBridge delegate was nil; wired ViewModel as delegate                                                                                     |
| 4  | The performance of text search is poor. I have to wait for a while each time I open the search panel. | Reader/*  | Medium   | FIXED    | SearchViewModel created before indexing; panel opens instantly, index builds in background                                                          |
| 5  | The performance of the text page is poor. I have to wait for a while each time I open a TXT book.     | TXT/*     | Medium   | FIXED    | NSAttributedString now built on background thread via TXTAttributedStringBuilder; UI shows spinner until ready                                      |
| 6  | The reading settings do not take effect.                                                              | Reader/*  | High     | FIXED    | settingsStore was created but never passed to reader host/container views; now wired through TXT and MD readers                                     |
| 7  | Scrolling performance is poor in the TXT reader.                                                      | TXT/*     | Medium   | FIXED    | Enabled allowsNonContiguousLayout + throttled scroll callbacks to \~10fps with end-of-scroll flush                                                  |
| 8  | There is nothing displayed on the reading panel.                                                      | Reader/*  | Medium   | FIXED    | Annotations panel had placeholder views; wired real BookmarkListView, HighlightListView, AnnotationListView, TOCListView with PersistenceActor      |
| 9  | The theme does not work in EPUB.                                                                      | EPUB/*    | High     | FIXED    | Threaded settingsStore into EPUB host/container/bridge; inject CSS via evaluateJavaScript on page load + live theme switch                          |
| 10 | Theme changes do not take effect in TXT without font size change or reopen.                           | TXT/*     | High     | FIXED    | configChanged in TXTTextViewBridge now compares textColor, backgroundColor, letterSpacing (was only fontSize/fontName/lineSpacing)                  |
| 11 | Opening a large TXT file causes very poor scrolling; nearly impossible to scroll.                     | TXT/*     | Medium   | FIXED    | Background attributed string build + allowsNonContiguousLayout + scroll throttling; main thread no longer blocks on NSAttributedString creation     |
| 12 | The toolbar cannot be hidden while reading.                                                           | Reader/*  | Medium   | FIXED    | Added isChromeVisible toggle; tap content to show/hide nav bar + status bar                                                                         |
| 13 | Large CJK TXT file (9.5MB) still has poor scrolling performance                                       | TXT/*     | High     | FIXED    | UITextView can't handle 9.5MB attributed string; switched to UITableView chunked renderer (TXTChunkedReaderBridge) for files > 500K UTF-16 units    |
| 14 | App startup and library page loading is too slow                                                      | Library/* | Medium   | FIXED    | Added isInitialLoad state to LibraryViewModel; LibraryView shows ProgressView during initial fetch instead of empty state flash                     |
| 15 | Observation tracking feedback loop — UITextView infinite layout invalidation, CPU 100%, app frozen    | Reader/*  | Critical | FIXED    | viewModel.currentOffsetUTF16 read in body created observation cycle; replaced with @State initialRestoreOffset + hasRestoredPosition one-shot flag  |
| 16 | Large CJK TXT file can't remember reading progress in chunked reader                                  | TXT/*     | High     | FIXED    | Same observation cycle as #15; fixed by capturing offset once after open, passing to bridge as fixed @State value                                   |
| 17 | Scrolling stuck and rebounds every time in TXT reader                                                 | Reader/*  | High     | FIXED    | Same root cause as #15 — restoreOffset re-applied on every scroll; removed updateUIView restore block, made restore one-shot in makeUIView only     |
| 18 | Failed to create 1206x0 image slot                                                                    | Library/* | Low      | WONT FIX | CoreGraphics cosmetic log noise from UIKit snapshot of zero-height cell during transitions; no user-visible impact                                  |
| 19 | All TXT files cannot remember reading progress                                                        | Reader/*  | High     | FIXED    | asyncAfter(0.15s) in makeUIView allows layout pass before scroll restore; was using async which ran before view had a valid frame                   |
| 20 | EPUB cannot hide the toolbar                                                                          | EPUB/*    | Medium   | FIXED    | WKWebView consumed tap events; added JS click handler + contentTapHandler WKScriptMessage + NotificationCenter                                      |
| 21 | TXT needs two clicks to hide toolbar                                                                  | TXT/*     | Medium   | FIXED    | UITextView consumed first tap; added UITapGestureRecognizer with shouldRecognizeSimultaneously + NotificationCenter                                 |
| 22 | Black padding at top after hiding toolbar                                                             | Reader/*  | Medium   | FIXED    | Added conditional .ignoresSafeArea(edges: .top) when chrome is hidden                                                                               |
| 23 | All TXT files cannot remember reading progress (regression of #19)                                    | Reader/*  | High     | FIXED    | Three fixes: scenePhase wiring, isOpenComplete race guard, scroll restore retry with frame-validity check                                           |
| 24 | Position save lost intermittently after reinstall (regression of #19/#23)                             | Reader/*  | Critical | FIXED    | onBackground() fire-and-forget Task raced with process suspension; made async + beginBackgroundTask; added scenePhase to EPUB/PDF                   |
| 25 | Position still drifts/resets on reopen (regression of #24)                                            | Reader/*  | Critical | FIXED    | TextKit 1 mode switch relayout resets contentOffset to 0; ghost scrollViewDidScroll overwrites saved position; suppressed with flag+time guards     |
| 26 | Position visually resets to top despite correct save (regression of #25)                              | Reader/*  | Critical | FIXED    | Suppress guards blocked bad saves but didn't re-apply visual position; added Phase 2 restore at t+0.8s after TextKit relayout settles               |
| 27 | Content flashes at beginning then jumps to saved position (UX)                                        | TXT/*     | Medium   | FIXED    | UITextView visible during 0.8s restore delay; hide with alpha=0 until Phase 2 completes, then fade in                                               |
| 28 | All the search results are the same                                                                   | Search/*  | High     | FIXED    | FTS5 snippet() is per-row; expanded occurrences shared same snippet; added source_texts table + per-occurrence snippet extraction                  |
| 29 | After changing font size, theme changes to different pattern                                          | TXT/*     | Medium   | FIXED    | attrStringKey excluded color properties; theme changes didn't trigger NSAttributedString rebuild; added color hashes to key                         |
| 30 | Reading settings bar too long, covering content                                                       | Reader/*  | Low      | FIXED    | Settings sheet presentationDetents included .large; constrained to .medium only                                                                     |
| 31 | Cannot add bookmarks, contents, highlights, or notes                                                  | Reader/*  | High     | FIXED    | No bookmark creation path; added NotificationCenter-based bookmark via toolbar button + modelContainer passthrough to all container views           |
| 32 | Cannot hide top and bottom bars in PDF files                                                          | PDF/*     | Medium   | FIXED    | PDFView internal gestures consumed taps; added UITapGestureRecognizer with shouldRecognizeSimultaneously + .readerContentTapped notification        |
| 33 | TXT files do not show reading time or remaining time                                                  | TXT/*     | Low      | FIXED    | No bottom overlay in TXT reader; added txtBottomOverlay showing progress % and session time                                                         |
| 34 | Sorting by reading time and last read is unavailable                                                  | Library/* | Medium   | FIXED    | ReadingStats.recompute(from:) never called; wired into all 4 ViewModel close() methods via PersistenceActor+Stats extension                         |
| 35 | Bottom bar does not share theme with top bar                                                          | Reader/*  | Low      | FIXED    | Overlays used .ultraThinMaterial (system theme); replaced with theme-matched colors + .toolbarColorScheme for nav bar                               |
| 36 | Cannot jump to searched location when tapped                                                          | Reader/*  | High     | FIXED    | onNavigate was a no-op stub; wired via .readerNavigateToLocator notification to all 4 format container views                                        |
| 37 | Theme/font changes take time to apply                                                                 | TXT/*     | Medium   | FIXED    | Loading spinner shown during settings-driven rebuild; changed to keep old content visible, only show spinner for initial load                       |
| 38 | Slow position restore on file reopen                                                                  | TXT/*     | Low      | FIXED    | Fixed 0.8s Phase 2 delay; added ensureLayout() for synchronous TextKit layout, reduced total to \~0.3s                                              |
| 39 | Bottom bar cannot be hidden when tapped                                                               | Reader/*  | Medium   | FIXED    | isChromeVisible only controlled nav bar; added local isChromeVisible to all container views, gated bottom overlays on it                            |
| 40 | Search navigation jumps to wrong location                                                             | Reader/*  | High     | FIXED    | Missing ensureLayout in search scroll path + missing match range in Locator; added ensureLayout + populated charRangeStart/End in resolver          |
| 41 | Slow position restore after reopening file (regression of #38)                                        | TXT/*     | Low      | FIXED    | Phase 2 delay 0.15s + fade-in 0.15s; reduced Phase 2 to 0.05s, removed animation                                                                    |
| 42 | Bookmarks cannot be edited or navigated                                                               | Reader/*  | High     | FIXED    | No-op onNavigate in annotations panel; wired all tabs + added bookmark rename via context menu + alert                                              |
| 43 | Search result not highlighted when navigated                                                          | Reader/*  | Medium   | FIXED    | No visual indicator at match; added highlightRange to bridge with yellow background attribute, auto-clears after 3s                                 |
| 44 | Cannot manually highlight or add notes                                                                | Reader/*  | High     | FIXED    | No edit menu for text selection; added Highlight/Add Note to UITextView edit menu via editMenuForTextIn + NotificationCenter to container views     |
| 45 | Books sorted by "Last Read" shows stale order                                                         | Library/* | Medium   | FIXED    | v5: recomputeStats() now always sets lastReadAt=Date() — sessions <5s were discarded leaving nil; DB now correct on refresh/restart                 |
| 46 | Manual highlight saves record but content not highlighted                                             | Reader/*  | Medium   | FIXED    | No visual feedback on save; added immediate highlightRange set in .readerHighlightRequested handler (3s auto-clear)                                 |
| 47 | App crashes after navigating to search result or bookmark then tapping screen                         | Reader/*  | Critical | FIXED    | v9: Full attributedText replacement + source-tracking in coordinator to break updateUIView↔addHighlightAttribute infinite loop                      |
| 48 | Highlight/note edit menu missing in large TXT files (chunked reader)                                  | TXT/*     | High     | FIXED    | TXTChunkedReaderBridge lacked UITextViewDelegate; added conformance + editMenuForTextIn with chunk offset translation                               |
| 49 | Annotation note input too narrow for long text                                                        | Reader/*  | Low      | FIXED    | .alert TextField is single-line; replaced with .sheet + AddNoteSheet using TextEditor for multi-line input                                          |
| 50 | Highlight/annotation navigation fails silently when tapped in panel                                   | Reader/*  | High     | FIXED    | LocatorFactory.txtRange didn't set charOffsetUTF16; added it + fallback to charRangeStartUTF16 in navigation handlers                               |
| 51 | Annotation notes don't show the original annotated text                                               | Reader/*  | Medium   | FIXED    | locator.textQuote already had the text; added display in AnnotationRowView as italicized quote above note content                                   |
| 52 | Large CJK TXT annotation panel navigation fails (chunked reader)                                      | TXT/*     | High     | FIXED    | Added scrollToOffset to chunked bridge + scrollToGlobalOffset with binary search chunk mapping + updateUIView handler                               |
| 53 | Highlight visual not applied in large CJK TXT (chunked reader)                                        | TXT/*     | Medium   | FIXED    | Added highlightRange to chunked bridge + applyHighlight with global-to-local range conversion + 3s auto-clear timer                                 |
| 54 | Highlight disappears in large CJK TXT after selecting other text and canceling                        | TXT/*     | Medium   | FIXED    | v2: Distinguish temporary (search) vs persistent (user) highlights — only auto-clear temporary; persistent keeps activeHighlight state indefinitely |
| 55 | Highlights not visible when file is reopened                                                          | Reader/*  | Medium   | FIXED    | Fetch highlights from DB on file open; pass as persistedHighlights to bridges; applied via HighlightableTextView\.addHighlightAttribute             |

