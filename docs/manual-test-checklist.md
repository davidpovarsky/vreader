# Manual Test Checklist

Test on device. Check off as verified. BLOCKED section at the bottom has known bugs — skip until fixed.

## Library

- [x] Sort order persists across app restart
- [x] View mode (grid/list) persists across restart
- [x] Long-press book → "Set Cover" → pick photo → cover appears
- [x] Long-press book → "Remove Cover" → reverts to default
- [x] Long-press book → Info sheet shows metadata
- [x] Long-press book → Share works
- [ ] Create collection → add books → collection appears
- [ ] Tag books → filter by tag
- [ ] Add OPDS catalog URL → browse books
- [ ] Download book from OPDS → appears in library

## Reader — Chrome & Navigation

- [x] Content scrolls normally in native mode
- [x] Tap center → toggles toolbar
- [x] Chrome toggle doesn't shift content
- [x] Top bar below Dynamic Island, matches bottom bar styling
- [ ] Library nav bar hidden during push transition
- [x] Reading progress bar visible and draggable
- [x] Bookmark button → haptic feedback + bookmark saved
- [x] Annotations tab order: Contents → Bookmarks → Highlights → Notes

## Reader — TOC

- [x] EPUB 3 nav.xhtml → real chapter titles (not "Section N")
- [x] EPUB 2 toc.ncx → real chapter titles
- [x] MD file → headings appear as TOC entries
- [x] TOC entries show indentation by level
- [x] Tap TOC entry → navigates to correct position

## Reader — Highlights & Annotations

- [x] TXT: select text → Highlight/Add Note in edit menu
- [x] PDF: select text → highlight annotation
- [ ] Delete highlight from panel → visual clears
- [x] Highlights visible on file reopen
- [ ] Export annotations → Markdown file
- [ ] Import annotations → highlights restored

## Reader — Dictionary & Translation

- [x] Select word → "Define" → system dictionary sheet
- [ ] Select word → "Translate" → AI translation panel

## Reader — AI

- [x] AI button visible when API key configured
- [ ] Summarize section → summary returned
- [x] Chat with book → multi-turn conversation works
- [x] General AI chat (from library) → works without book context

## Reader — TTS

- [ ] Tap speaker icon → TTS starts reading
- [ ] Control bar: play/pause, stop, speed slider
- [x] TTS button hidden for PDF

## Reader — Text Transforms

- [ ] Toggle Simp→Trad → Chinese text converts
- [ ] Toggle Trad→Simp → converts back
- [ ] Add replacement rule → text cleaned
- [ ] Highlights/search still work after transforms

## Reader — Performance

- [ ] Large TXT (\~15MB) opens in under 2s
- [ ] Search panel opens instantly
- [ ] Second open skips indexing
- [ ] AI/search/TOC only load when invoked

## Reader — Search

- [x] Search results show with query terms highlighted
- [x] Tap result → navigates to correct location
- [ ] Search highlight auto-clears on next action

## Book Sources (#24)

- [ ] Import Legado source JSON → source appears
- [ ] Search via source → results displayed
- [ ] Tap chapter → content loads
- [ ] Chapters cached for offline reading

## Sync

- [ ] WebDAV backup → archive on server
- [ ] WebDAV restore → data recovered
- [ ] HTTP TTS → cloud voice reads

## Latest Fixes (2026-03-22)

### #95 — Translate opens correct tab

- [x] Select word in TXT → "Translate" → AI panel opens on Translate tab (not Summarize)
- [ ] Open AI panel via toolbar → opens on Summarize tab (default)
- [ ] Swipe-dismiss AI panel → next open defaults to Summarize

### #96 — TTS produces sound

- [ ] Tap speaker icon → audio plays from speaker
- [ ] Stop → audio stops, other app audio resumes (not ducked)

### #101 — Book sources visible after import

- [ ] Settings → Book Sources → import Legado JSON → sources appear in list
- [ ] Search button active after import

### #100 — Book source saves persist

- [ ] Create new source → close/reopen app → still there

### #92 — AI reads actual content

- [ ] Open GBK/Big5 TXT → AI summarize → shows real content (not just title)
- [ ] Chat with book → AI references actual text

### #89 — Books open faster

- [ ] Open any book → content appears without noticeable delay
- [ ] Search panel opens instantly

---

## BLOCKED — Known Bugs / Missing UI (skip until fixed)

### Paged Mode (bug #82)

- [ ] Settings → paged layout → content paginates (not scrolls)
- [ ] Page turn animations (slide/cover/none)
- [ ] Auto page turn at configurable interval

### TXT TOC (bug #83)

- [ ] TXT with Chinese chapters (第一章) → TOC populated
- [ ] TXT with English chapters (Chapter 1) → TOC populated

### EPUB Highlights (bug #77)

- [ ] EPUB: select text → highlight confirmation dialog

### Per-Book Settings (feature #37, bug #84)

- [ ] Toggle "Custom settings for this book" → only affects this book

### Tap Zone Settings (feature #25 — no settings UI)

- [ ] Configurable in settings (left/center/right actions)

### Theme Background Image (feature #32 — no image picker UI)

- [ ] Pick background image from photos

### iCloud Backup (feature #10 — not implemented)

- [ ] iCloud backup and restore

