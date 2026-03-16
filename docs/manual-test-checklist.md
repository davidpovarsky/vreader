# V2 Manual Test Checklist

Test on device after each phase. Check off as verified.

## Phase 0 — Foundation

- [ ] Large TXT file (~15MB) opens in under 2s
- [ ] Second open of same book skips indexing (instant search available)
- [ ] Search works after reopening a previously indexed book
- [ ] ReadingMode toggle appears in settings (Native / Unified)
- [ ] Unified mode shows placeholder for EPUB (Phase B replaces this)
- [ ] PDF ignores Unified setting (always Native)

## Phase A — Quick Wins

- [ ] Search results bold/highlight the query term in snippets
- [ ] Multi-word query highlights each word independently
- [ ] Long-press book → "Set Cover" → pick photo → cover appears in library
- [ ] Long-press book → "Remove Cover" → reverts to default
- [ ] Tap left zone → previous page action fires (no-op until Phase B pagination)
- [ ] Tap center zone → toggles toolbar
- [ ] Tap right zone → next page action fires
- [ ] Settings → enable custom background → pick image → shows behind reader text
- [ ] Background opacity slider works
- [ ] Per-book settings toggle → change font size → only affects this book
- [ ] Other books still use global settings

## Phase B — Reader Core

### TXT TOC (B01)
- [ ] Open TXT file with Chinese chapters (第一章...) → TOC populated
- [ ] Open TXT file with English chapters (Chapter 1...) → TOC populated
- [ ] Tap TOC entry → navigates to correct position
- [ ] TXT file without chapters → empty TOC (no crash)

### Dictionary (B02)
- [ ] Select word in TXT → edit menu shows "Define" and "Translate"
- [ ] Tap "Define" → system dictionary sheet opens
- [ ] Tap "Translate" → AI translation panel opens with selected text

### TTS (B03)
- [ ] Tap speaker icon in toolbar → TTS starts reading
- [ ] TTS control bar appears at bottom (play/pause, stop, speed slider)
- [ ] Pause → resume works
- [ ] Speed slider changes reading speed
- [ ] Stop → control bar hides
- [ ] TTS button hidden for PDF (no .tts capability)

### Native EPUB Paged (B06)
- [ ] Settings → EPUB Layout → Paged
- [ ] EPUB renders as pages (no vertical scroll)
- [ ] Tap right zone → next page
- [ ] Tap left zone → previous page
- [ ] Switch back to Scroll → continuous scroll restored

### Native TXT/MD Paged (B08)
- [ ] Paged layout mode → TXT shows as pages
- [ ] Page navigation via tap zones works

### Native PDF Page Nav (B09)
- [ ] Tap right zone → next PDF page
- [ ] Tap left zone → previous PDF page
- [ ] At last page → right tap is no-op
- [ ] At first page → left tap is no-op

### Unified TXT Engine (B04)
- [ ] Settings → Engine: Unified → TXT file renders via TextKit 2
- [ ] Scroll mode → continuous scroll works
- [ ] Paged mode → pages display correctly
- [ ] Font size change → pages recalculate
- [ ] Switch back to Native → original UITextView renderer
- [ ] Reading position preserved across mode switch
- [ ] CJK text renders correctly

### Unified MD (B05)
- [ ] Unified mode → MD file renders via TextKit 2
- [ ] Attributed text (bold, italic, headings) preserved

### Unified EPUB (B07)
- [ ] Simple EPUB → renders in Unified engine
- [ ] Complex EPUB (tables/math) → falls back to Native WKWebView

### Auto Page Turn (B10)
- [ ] Enable auto page → pages turn automatically at set interval

### Page Turn Animations (B11)
- [ ] Slide animation → page slides horizontally
- [ ] Cover animation → page cover-flips
- [ ] None → instant page switch

### Pagination Cache (B13)
- [ ] Change font size while paged → pages recalculate immediately
- [ ] Rotate device → pages recalculate for new viewport

## Phase C — Library

- [ ] Create collection → add books → collection appears in library
- [ ] Tag books → filter by tag
- [ ] Export annotations → Markdown file with highlights + notes
- [ ] Import annotations → highlights restored from file
- [ ] Add OPDS catalog URL → browse available books
- [ ] Download book from OPDS → appears in library

## Phase D — Web Content (Book Source)

- [ ] Import Legado source JSON → source appears in list
- [ ] Search via source → book results displayed
- [ ] Tap book → info page with chapters
- [ ] Tap chapter → content loads and displays
- [ ] Chapters cached for offline reading
- [ ] Close and reopen → cached chapters load instantly
- [ ] Enable/disable source → affects search results

## Phase E — Sync & Text

- [ ] WebDAV backup → creates archive on server
- [ ] WebDAV restore → data recovered
- [ ] iCloud backup → data syncs
- [ ] Toggle Simp→Trad → Chinese text converts in reader
- [ ] Toggle Trad→Simp → converts back
- [ ] Highlights/search still work after text conversion
- [ ] Add replacement rule → text cleaned in reader
- [ ] HTTP TTS → cloud voice reads text
