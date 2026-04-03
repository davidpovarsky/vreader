# Manual Test Checklist

Test on device (iPhone 17 Pro simulator or physical). Check off as verified.
Last regenerated: 2026-04-04.

---

## Library

- [x] Sort order persists across app restart
- [x] View mode (grid/list) persists across restart
- [x] Long-press book → "Set Cover" → pick photo → cover appears
- [x] Long-press book → "Remove Cover" → reverts to default
- [x] Long-press book → Info sheet shows metadata
- [x] Long-press book → Share works
- [ ] 3-column grid layout with uniform card heights
- [ ] EPUB cover extracted and displayed on import
- [ ] AZW3/MOBI cover extracted and displayed on import
- [ ] Books without covers show colored placeholder with format icon
- [ ] Delete book → cover file removed from disk
- [ ] Create collection → add books → collection appears in sidebar
- [ ] Tag books → filter by tag in sidebar
- [ ] Series grouping appears in sidebar

## OPDS Catalog (feature #36)

- [ ] Add OPDS catalog URL → browse remote books
- [ ] Download book from OPDS → appears in library

## Reader — Chrome & Navigation

- [x] Content scrolls normally in native mode
- [x] Tap center → toggles toolbar (top + bottom)
- [x] Chrome toggle doesn't shift content
- [x] Top bar below Dynamic Island, matches bottom bar styling
- [x] Library nav bar hidden during push transition
- [x] Reading progress bar visible and draggable
- [x] Bookmark button → haptic feedback + bookmark saved
- [x] Annotations tab order: Contents → Bookmarks → Highlights → Notes

## Reader — TOC

- [x] EPUB 2 toc.ncx → real chapter titles
- [x] MD file → headings appear as TOC entries
- [x] TOC entries show indentation by level
- [x] Tap TOC entry → navigates to correct position
- [ ] TXT with Chinese chapters (第一章) → TOC populated
- [ ] TXT with English chapters (Chapter 1) → TOC populated

## Reader — Highlights & Annotations

- [x] TXT: select text → Highlight/Add Note in edit menu
- [x] TXT (large/chunked): select text → Highlight/Add Note works
- [x] PDF: select text → highlight annotation
- [x] Highlights visible on file reopen
- [ ] EPUB: select text → highlight (bug #103 — JS race)
- [ ] Delete highlight from panel → visual clears in reader
- [ ] Export annotations → Markdown/JSON file
- [ ] Import annotations → highlights restored in reader

## Reader — Dictionary & Translation

- [x] Select word → "Define" → system dictionary sheet
- [ ] Select word → "Translate" → AI translation tab opens (not Summarize)

## Reader — AI

- [x] AI button visible only when API key configured + consent on
- [x] Chat with book → multi-turn conversation works
- [x] General AI chat (from library) → works without book context
- [ ] Summarize section → summary returned
- [ ] Open AI panel via toolbar → opens on Summarize tab (default)
- [ ] Open GBK/Big5 TXT → AI summarize → shows real content (not mojibake)

## Reader — TTS (feature #26)

- [ ] Tap speaker icon → TTS starts reading aloud
- [ ] Control bar: play/pause, stop, speed slider
- [ ] TTS auto-scrolls to current sentence
- [ ] Current sentence highlighted during speech
- [ ] Stop TTS → bottom bar reappears
- [x] TTS button hidden for PDF

## Reader — Paged Mode (feature #21)

- [ ] Settings → paged layout → content paginates (not scrolls)
- [ ] Page turn animations (slide/cover/none)
- [ ] Auto page turn at configurable interval (feature #31)
- [ ] Mode switch preserves reading position

## Reader — Text Transforms

- [ ] Toggle Simp→Trad → Chinese text converts
- [ ] Toggle Trad→Simp → converts back
- [ ] Add replacement rule → text cleaned
- [ ] Highlights/search still work after transforms

## Reader — Settings

- [ ] Per-book settings: toggle "Custom for this book" → only affects this book
- [ ] Tap zone config: left/center/right actions configurable
- [ ] Theme background image: pick photo, adjust opacity

## Reader — Search

- [x] Search results show with query terms bold/highlighted
- [x] Tap result → navigates to correct location with highlight
- [ ] Search highlight auto-clears on next action (feature #5)

## Reader — Performance

- [ ] Large TXT (~15MB) opens in under 2s
- [ ] Search panel opens instantly (no indexing wait)
- [ ] Second open skips indexing (persistent FTS5)
- [ ] AI/search/TOC only load when invoked (lazy setup)

## Book Sources (feature #24)

- [ ] Import Legado source JSON → sources appear in list
- [ ] Search via source → results displayed
- [ ] Tap chapter → content loads
- [ ] Chapters cached for offline reading
- [ ] Create new source → close/reopen → still there

## Sync — WebDAV (feature #29)

- [ ] Configure WebDAV server in settings
- [ ] Backup → archive uploaded to server
- [ ] Restore → data recovered from server

## Sync — iCloud (feature #10)

- [ ] Not implemented (deferred)

---

## Open Bugs

| Bug | Summary | Severity |
|-----|---------|----------|
| #90 | AI buttons visible when consent off | Medium |
| #91 | Blank panel on Translate without AI configured | Medium |
| #93 | Chat sessions not persisted across panel dismiss | Medium |
| #94 | Keyboard can't dismiss in chat | Low |
| #99 | Search highlight missing in some TXT files | Medium |
| #103 | Cannot add highlight in native EPUB (JS race) | High |
| #104 | EPUB 3 nav titles not extracted (REOPENED) | Medium |
| #105 | Highlighted snippet multi-word overlap | Low |
| #107 | Cover art with white edges shows "padding" illusion | Low |

## Open Features

| Feature | Summary | Priority | Status |
|---------|---------|----------|--------|
| #5 | Search highlight auto-dismiss | Low | Code done, unverified |
| #10 | iCloud backup | Medium | Deferred |
| #29 | WebDAV backup | Medium | Code done, unverified |
| #36 | OPDS catalog | Medium | Code done, unverified |
| #42 | Foliate-js unified reader (GH #113) | High | Planned |
| #43 | Cover image extraction (GH #121) | Medium | Done, pending commit |
