# Bug History (Archived)

Historical descriptions, root causes, solutions, and lessons for all bugs.
Moved from `docs/bugs.md` to reduce file size. The Summary table in `docs/bugs.md` is the source of truth for status.

## Original Descriptions

1. CJK search returns no results
2. The search results are incomplete; only a few results are shown.
3. Progress cannot be saved. Each time the TXT file is opened, it starts from the beginning.
4. The performance of text search is poor. I have to wait for a while each time I open the search panel.
5. The performance of the text page is poor. I have to wait for a while each time I open a TXT book.
6. The reading settings do not take effect.
7. Scrolling performance is poor in the TXT reader.
8. There is nothing displayed on the reading panel.
9. The theme does not work in EPUB.
10. Theme changes do not take effect in TXT; they only apply after changing the font size or reopening the file.
11. Opening a large TXT file causes very poor scrolling performance; the page is nearly impossible to scroll, and scrolling is not smooth.
12. The toolbar cannot be hidden while reading.
13. @'/Users/ll/Downloads/黑暗血时代世界观设定+剧情整理（起点活动）第十五卷生存之战（未完待续） (1).txt' #11,#7 bug still exist
14. It takes too long to start the app and open the library page.
15. Observation tracking feedback loop — UITextView infinite layout invalidation, CPU 100%, app frozen, can't scroll or navigate back
16. Large CJK TXT file can't remember reading progress
17. Scrolling stuck and rebounds every time in another TXT file
18. Failed to create 1206x0 image slot (alpha=1 wide=1) (client=0xda0b106d) [0x5 (os/kern) failure]
19. All TXT files cannot remember the reading progress.
20. EPUB cannot hide the toolbar.
21. After opening a TXT file, it takes two clicks to hide the toolbar instead of one.
22. After hiding the toolbar, there is black padding at the top.
23. All TXT files cannot remember the reading progress. #19, The progress is lost again.
24. The bug #19, #23 is not fixed. It happens after reinstalling the app, but disappears after a while. Sometimes it restores the progress; sometimes it is lost and the file reopens at the beginning. It seems to vary depending on how long the file remains open. The progress must not be lost.
25. The bug #19, #23,#24 is not fixed.
26. The bug #19, #23,#24 ,#25is not fixed.
27. It is unacceptable for a TXT file to start at the beginning and then jump to the last read position.
28. All the search results are the same.
29. After changing the font size, the theme changes to a different pattern.
30. The reading settings bar is too long, covering the content and making it difficult to preview the changes.
31. Cannot add bookmarks, contents, highlights, or notes.
32. Cannot hide the top and bottom bars in PDF files.
33. TXT files do not show the reading time or the remaining time.
34. The sorting feature for books by reading time and last read is unavailable.
35. The bottom bar does not share the same theme as the top bar.
36. Cannot jump to the searched location when tapped.
37. It takes time for the changes to take effect after the theme or font size is changed.
38. It takes time to jump to the saved progress after reopening the file.
39. The bottom bar cannot be hidden when tapped.
40. Cannot jump to the searched location when tapped. It jumped, but not to the correct location.
41. It takes time to jump to the saved progress after reopening the file. # 38 I have to wait for a while.
42. Bookmarks cannot be edited and cannot jump to the location when tapped.
43. The search result is not highlighted when jumped to.
44. Cannot manually highlight or add notes.
45. Books sorted by "Last Read" do not take effect.
46. Manual highlight saves record but content not highlighted.
47. The app flashes and exits when jumping to a search result and tapping the screen. Also crashes on bookmark navigation + double tap.
48. The highlight and note features do not appear in some TXT files (large CJK files using chunked reader).
49. The input box is too narrow when adding a note with a long paragraph.
50. It cannot jump to the location when highlights or notes are tapped in the annotations panel.
51. The notes do not show the original content, so I cannot tell what the notes refer to.
52. Large CJK TXT files cannot jump to the location when notes, highlights, or bookmarks are tapped in the annotations panel.
53. Manual highlight saves record but content is not visually highlighted in large CJK TXT files (chunked reader).
54. Highlight disappears in large CJK TXT after selecting other text and canceling.

## Causes

- **#13**: UITextView with TextKit 1 allocates glyph storage for the entire NSAttributedString upfront (~65MB for a 9.5MB CJK file). Even with `allowsNonContiguousLayout`, the initial allocation and layout computation causes extreme scroll jank because UITextView must manage millions of glyphs in a single text container.
- **#14**: `LibraryView` checked `viewModel.isEmpty` immediately on appear — before `loadBooks()` had a chance to run. Since `books` starts empty, the empty state ("Your Library is Empty") flashed briefly before the actual book list loaded, making the app feel slow.
- **#15, #17**: `TXTReaderContainerView` (and `MDReaderContainerView`) passed `viewModel.currentOffsetUTF16` — an `@Observable` property that changes on every scroll — directly to the bridge as `restoreOffset`. This created an observation feedback loop: scroll -> viewModel update -> SwiftUI re-render -> `restoreScrollPosition` -> scroll again, infinitely.
- **#16**: The chunked reader's `restoreChunkIndex()` also read `viewModel.currentOffsetUTF16` in the body (same observation cycle). Additionally, position restore only worked in `makeUIView`, not on subsequent renders.
- **#19**: The one-shot scroll position restore in `TXTTextViewBridge.makeUIView` used `DispatchQueue.main.async`, but the UITextView hasn't been sized by SwiftUI at that point. TextKit's `lineFragmentRect` returns `CGRect.zero` when the text container has zero width.
- **#20**: WKWebView in `EPUBWebViewBridge` intercepts all tap events through its internal gesture recognizers. SwiftUI's `onTapGesture` modifier on the parent `ReaderContainerView` never fires because UIKit gesture recognizers have priority.
- **#21**: `UITextView` with `isSelectable = true` has internal gesture recognizers that consume single-tap events (for cursor placement).
- **#22**: When `.toolbar(.hidden, for: .navigationBar)` and `.statusBarHidden(true)` are applied, the safe area inset remains. The content doesn't extend into the vacated area.
- **#23**: Three compounding issues: (1) No `scenePhase` wiring for `onBackground()`/`onForeground()`. (2) `close()`/`open()` race condition at `positionStore.loadPosition()` suspension point. (3) `asyncAfter(0.15s)` one-shot scroll restore had no fallback if the view still had no valid frame.
- **#24**: `onBackground()` used a fire-and-forget `Task` that required an async actor hop to `PersistenceActor`. iOS could suspend the process before the hop completed.
- **#25**: TextKit 1 compatibility mode switch triggers a full relayout that resets `contentOffset` to near zero. Ghost `scrollViewDidScroll` overwrites saved position.
- **#26**: The #25 fix suppressed ghost scroll callbacks but did NOT fix the visual position. TextKit relayout happened AFTER Phase 1 restore and physically reset `contentOffset` to 0.
- **#27**: UX issue: Phase 2 restore (t+0.8s) works correctly, but UITextView is visible showing content at offset 0 for ~0.8s before jumping.
- **#28**: FTS5 `snippet()` returns one snippet per database row, but `findAllMatchOffsets` expands each row to multiple hit occurrences. All shared the same snippet.
- **#29**: `attrStringKey` excluded `textColor` and `backgroundColor`, so theme changes didn't trigger NSAttributedString rebuild.
- **#30**: Settings sheet used `.presentationDetents([.medium, .large])`, allowing full height.
- **#31**: No bookmark creation mechanism existed. No way to trigger from toolbar or pass model container to format-specific views.
- **#32**: Same root cause as #20/#21 — PDFView's internal gesture recognizers consume tap events.
- **#33**: No bottom overlay in TXT reader for reading progress or session time.
- **#34**: `ReadingStats.recompute(from:)` existed but was never called. Stats remained at initial values.
- **#35**: Bottom overlays used `.ultraThinMaterial` (system theme), not reader's custom theme.
- **#36**: `onNavigate` callback was a no-op stub.
- **#37**: Loading spinner shown during settings-driven rebuilds. Should keep old content visible.
- **#38**: Position restore used a fixed 0.8s Phase 2 delay. TextKit layout often completes much faster.
- **#39**: `isChromeVisible` only controlled nav bar. Bottom overlays had no access to it.
- **#40**: (1) `allowsNonContiguousLayout` causes estimated line heights for unvisited regions. (2) `SearchHitToLocatorResolver` didn't populate `charRangeStartUTF16`/`charRangeEndUTF16`.
- **#41**: Phase 1 + Phase 2 delay totaling ~0.3s, with fade-in animation on top.
- **#42**: `AnnotationsPanelSheet` had no-op `onNavigate` closures. `BookmarkPersisting` lacked `updateBookmarkTitle`.
- **#43**: Bridge scrolled to offset but applied no visual indicator on matched text.
- **#44**: No UI to create highlights or notes from selection. UITextView only offered Copy/Select All.
- **#45**: v1-v2: `.task` only runs once + throttle blocked refresh. v3: `markBookAsJustRead()` updated in-memory then called `await loadBooks()` which re-fetched from DB before `recomputeStats()` committed, overwriting the fix with stale data. Root cause: calling `loadBooks()` immediately after an in-memory fix when the DB write hasn't committed yet.
- **#46**: Highlight action saved record but never set `highlightRange` state for visual feedback.
- **#47**: v1-v2: Unsigned integer underflow + missing bounds guards. v3: Timer callbacks in both `TXTChunkedReaderBridge` and `TXTTextViewBridge` accessed UIKit objects (`textStorage.removeAttribute`, `tableView.visibleCells`) without `DispatchQueue.main.async`. When main thread was blocked in TextKit 1 relayout (holding `os_unfair_lock`), Timer fired on background thread → lock ownership violation → crash.
- **#48**: `TXTChunkedReaderBridge` lacked `UITextViewDelegate` conformance. No custom edit menu for large CJK files.
- **#49**: "Add Note" used `.alert` with `TextField` — inherently single-line.
- **#50**: `LocatorFactory.txtRange()` set range fields but not `charOffsetUTF16`. Navigation handler guarded on it, silently dropping.
- **#51**: `AnnotationRowView` only displayed note text, not the original annotated text from `locator.textQuote`.
- **#52**: `chunkedReaderContent()` did not pass `scrollToOffset` to `TXTChunkedReaderBridge`.
- **#53**: Same as #52 — `highlightRange` not passed to chunked bridge.
- **#54**: v1: Cell reuse wiped highlights + missing `textViewDidChangeSelection`. v2: 3-second auto-clear timer cleared `activeHighlightChunkIndex`/`activeHighlightLocalRange`, destroying the persistent state needed for cell reuse re-application. No distinction between temporary (search nav) and persistent (user-created) highlights — both treated as temporary.

## Solutions

- **#13**: Added `TXTTextChunker` + `TXTChunkedReaderBridge` (UITableView). Files >500K UTF-16 use chunked renderer.
- **#14**: Added `isInitialLoad` property to `LibraryViewModel`. Shows `ProgressView` during initial fetch.
- **#15, #16, #17**: Replaced live `viewModel.currentOffsetUTF16` with `@State var initialRestoreOffset` captured once. Made restore one-shot in `makeUIView` only.
- **#19**: Changed `DispatchQueue.main.async` to `asyncAfter(0.15s)` for layout pass.
- **#20, #21**: Added `UITapGestureRecognizer` with `shouldRecognizeSimultaneously` + `NotificationCenter`.
- **#22**: Added `.ignoresSafeArea(edges: .top)` when chrome is hidden.
- **#23**: Three fixes: scenePhase wiring, `isOpenComplete` race guard, scroll restore retry.
- **#24**: Made `onBackground()` async + `beginBackgroundTask`. Added scenePhase to EPUB/PDF.
- **#25**: `suppressScrollCallbacks` flag + time-based `restoreSuppressUntil` guard.
- **#26**: Two-phase scroll restore. Phase 2 at t+0.8s re-applies after TextKit relayout settles.
- **#27**: Hide UITextView (`alpha = 0`) until Phase 2 completes, then fade in.
- **#28**: Added `source_texts` table + per-occurrence `extractSnippet()`.
- **#29**: Added textColor/backgroundColor hash to `attrStringKey`.
- **#30**: Changed `.presentationDetents` to `[.medium]` only.
- **#31**: Added `NotificationCenter`-based bookmark creation via toolbar button + `modelContainer` passthrough.
- **#32**: Added `UITapGestureRecognizer` to `PDFViewBridge.Coordinator`.
- **#33**: Added `txtBottomOverlay` showing progress % and session time.
- **#34**: Created `PersistenceActor+Stats.swift`. Wired into all 4 ViewModel `close()` methods.
- **#35**: Replaced `.ultraThinMaterial` with theme-matched colors + `.toolbarColorScheme`.
- **#36**: Wired `onNavigate` via `.readerNavigateToLocator` notification.
- **#37**: Changed to `isBuildingInitialAttrString` — only spinner for initial load.
- **#38**: Added `ensureLayout(forCharacterRange:)` before Phase 1. Reduced Phase 2 to 0.15s.
- **#39**: Added `isChromeVisible` to all container views, gated bottom overlays.
- **#40**: Added `ensureLayout` in search path + populated `charRangeStart/End` in resolver.
- **#41**: Reduced Phase 2 to 0.05s, removed fade-in animation.
- **#42**: Wired all `AnnotationsPanelSheet` tabs + added bookmark rename via context menu.
- **#43**: Added `highlightRange` to bridge with yellow background attribute, auto-clears after 3s.
- **#44**: Added `editMenuForTextIn:suggestedActions:` with Highlight/Add Note actions + `NotificationCenter`.
- **#45**: v1: `.onAppear` refresh. v2: Event-driven `.readerDidClose` notification. v3: In-memory `lastReadAt` update + `loadBooks()`. v4: Remove `loadBooks()` — it overwrote the in-memory fix with stale DB data.
- **#46**: Set `highlightRange` immediately in `.readerHighlightRequested` handler.
- **#47**: v1: Bounds guard before unsigned subtraction. v2: Defensive guards in chunked `applyHighlight`. v3: Wrap all Timer callbacks in `DispatchQueue.main.async` — Timer can fire off-main when main thread is blocked in TextKit relayout.
- **#48**: Added `UITextViewDelegate` to `TXTChunkedReaderBridge.Coordinator` + `editMenuForTextIn` with chunk offset translation.
- **#49**: Created `AddNoteSheet.swift` with `TextEditor` for multi-line input.
- **#50**: Added `charOffsetUTF16 = charRangeStartUTF16` fallback in `LocatorFactory` + navigation handlers.
- **#51**: Added display of `locator.textQuote` in `AnnotationRowView`.
- **#52**: Added `scrollToOffset` to chunked bridge + `scrollToGlobalOffset` with binary search.
- **#53**: Added `highlightRange` to chunked bridge + `applyHighlight` with global-to-local conversion.
- **#54**: v1: Track active highlight on Coordinator; re-apply in `cellForRowAt`. v2: Distinguish temporary (search nav) vs persistent (user-created) highlights — only auto-clear temporary; persistent keeps `activeHighlight*` state indefinitely.

## Lessons

- TextKit 1 can't handle multi-megabyte attributed strings. Use virtualized rendering (UITableView) for large documents.
- Distinguish "not loaded yet" from "loaded and empty" in ViewModel state.
- Never read a rapidly-mutating `@Observable` property in SwiftUI body that feeds back to the same `UIViewRepresentable`. Use `@State` for one-shot values.
- `DispatchQueue.main.async` in `makeUIView` is unreliable for layout-dependent operations. Use `asyncAfter` with delay or check `bounds.width > 0` with retry.
- UIKit gesture recognizers in `UIViewRepresentable` intercept touches before SwiftUI gesture modifiers. Use `shouldRecognizeSimultaneously`.
- `@MainActor` async methods can interleave at `await` suspension points. Use generation counters and completion flags.
- Never use fire-and-forget `Task {}` for critical saves in `onBackground()` or `.onDisappear`. Make async + `beginBackgroundTask`.
- Every reader container view must wire `@Environment(\.scenePhase)`.
- TextKit 1 compatibility mode switch destroys scroll position. Suppress callbacks + re-apply position after relayout.
- Distance-based scroll guards are insufficient for layout storms. Use time-based or flag-based suppression.
- Suppressing callbacks is not enough — the visual position must also be re-applied.
- Hide content during async position restore to avoid jarring jumps.
- FTS5 `snippet()` is per-row, not per-occurrence.
- Composite keys for `@Observable`-driven rebuilds must include ALL mutable properties.
- Sheet `.presentationDetents` should match the use case.
- `NotificationCenter` is the right cross-view communication pattern when views don't share a direct data path.
- UIKit views with internal gesture recognizers need `shouldRecognizeSimultaneously` for tap coexistence.
- Wire computed stats to lifecycle events, not just data mutations.
- Reader chrome must use the reader's theme, not system theme.
- Never leave stub callbacks in shipping code.
- Show old content during settings-driven rebuilds.
- Use `ensureLayout(forCharacterRange:)` instead of fixed delays for TextKit layout.
- Search result match ranges must travel end-to-end through the pipeline.
- Temporary visual highlights should auto-clear.
- `textView(_:editMenuForTextIn:suggestedActions:)` (iOS 16+) is the cleanest way to add custom edit menu actions.
- `.task` in SwiftUI only runs once per view lifetime. Use `.onAppear` with throttled refresh for updates.
- Throttles can silently drop critical refreshes. Add a `force` parameter for known-stale scenarios.
- SwiftUI `@State` survives re-renders — stale navigation state can re-apply. Guard with bounds checks.
- Guard unsigned integer subtraction BEFORE performing it.
- Feature parity across rendering paths must be explicit. Check alternative bridges when adding features.
- Chunk-local offsets must be translated to document-global offsets.
- SwiftUI `.alert` with `TextField` is single-line. Use `.sheet` with `TextEditor` for multi-line input.
- Range-based locators should also set point offsets for navigation compatibility.
- Data already in the model often doesn't need schema changes.
- Never use fixed delays to coordinate async operations across views. Use event-driven signaling.
- Every feature wired to a standard bridge must also be wired to the alternative bridge.
- Chunk-based rendering requires coordinate translation in both directions.
- Never call `loadBooks()` (DB re-fetch) immediately after an in-memory fix — the DB write may not have committed yet. Trust the in-memory state for immediate UI; let eventual consistency handle the rest.
- Always wrap Timer callbacks in `DispatchQueue.main.async` when accessing UIKit objects. Even main-runloop Timers can fire off-main when the main thread is blocked in framework code (e.g., TextKit relayout).
- Distinguish temporary visual feedback (auto-clear after N seconds) from persistent user-created state. Use separate state variables or type flags to prevent auto-clear from destroying persistent data.

### Bug #45 v5 — "Last Read" sort resets on refresh/restart
- **Root cause**: `recomputeStats()` derived `lastReadAt` from session `endedAt`, but sessions shorter than 5s were discarded by `ReadingSessionTracker` (minimum duration threshold). Quick opens/closes left `lastReadAt` nil. The v4 in-memory fix via `markBookAsJustRead()` worked until `loadBooks()` re-fetched stale DB data.
- **Solution**: Added `stats.lastReadAt = Date()` after `stats.recompute(from:)` in `recomputeStats()`. Since this method is only called from reader `close()`, "now" is always correct. DB now has reliable `lastReadAt` that survives refresh/restart.
- **Lessons**: Session-based derived timestamps can have gaps when sessions are filtered. If a timestamp should always be set on a lifecycle event (close), set it explicitly rather than deriving from filtered data.

### Bug #47 v4 — Crash on highlight (os_unfair_lock_unowned_abort)
- **Root cause**: `textStorage.addAttribute()` triggers synchronous TextKit 1 relayout. During relayout, delegate callbacks (scrollViewDidScroll, textViewDidChangeSelection) can fire, accessing `textStorage` reentrantly. The reentrant access attempts to acquire an already-held `os_unfair_lock` → crash. CJK text exacerbates this because layout is more complex and takes longer.
- **Solution**: Wrapped all `textStorage.addAttribute()` and `removeAttribute()` calls in `beginEditing()/endEditing()` pairs in both `TXTTextViewBridge` and `TXTChunkedReaderBridge`. This batches changes and defers notifications until `endEditing()`, preventing reentrant access.
- **Lessons**: Never modify `NSTextStorage` attributes without `beginEditing()/endEditing()`. TextKit 1 relayout is synchronous and can trigger delegate callbacks that re-enter textStorage. The crash is intermittent because it depends on layout timing. `DispatchQueue.main.async` doesn't help because it's already on main — the issue is reentrant same-thread access.

### Bug #55 — Highlights not visible when file is reopened
- **Root cause**: Highlights were correctly persisted to DB via `PersistenceActor.addHighlight()`, but no code loaded persisted `HighlightRecord`s on file open and applied their character ranges as background colors to the text view.
- **Solution**: Added `persistedHighlights: [NSRange]` parameter to both `TXTTextViewBridge` and `TXTChunkedReaderBridge`. Container views (`TXTReaderContainerView`, `MDReaderContainerView`) fetch highlights via `persistence.fetchHighlights()` in their `.task` block after file open. Ranges are applied in `makeUIView` (small files) and `cellForRowAt` (chunked reader), all wrapped in `beginEditing()/endEditing()`.
- **Lessons**: Persisting data is only half the story — loading and rendering it on the display path must also be implemented. When adding a "save" feature, always plan the "load and display" counterpart.
