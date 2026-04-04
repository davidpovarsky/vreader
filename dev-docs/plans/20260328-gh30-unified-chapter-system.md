# GH #30: Unified TXT Chapter System

**Date**: 2026-03-28
**Status**: DRAFT
**Issue**: #30 — TOC jumps to wrong chapter + wrong position + position restore broken

## Problem Statement

The TXT reader has two separate chapter systems that produce incompatible results for multi-byte encodings (GBK, Big5, Shift_JIS):

| System | How it builds | Coordinate type | Used by |
|--------|--------------|-----------------|---------|
| **TOC** (`TXTTocRuleEngine`) | Full-text decode → regex | UTF-16 offsets | TOC display, active chapter highlight |
| **Chapter Index** (`TXTChapterIndexBuilder`) | 512KB streaming blocks → regex → byte offsets | Byte offsets (UTF-16 populated later) | Content loading, navigation, position save/restore |

**Why they drift**: Per-block decode of GBK byte ranges fails when block boundaries split multi-byte characters. This produces garbled titles, wrong byte-to-UTF-16 mappings, and eventually silent fallback to full-text mode.

## Target Architecture (Legado Strategy)

**One system**: Decode file once → run regex once → produce chapters with UTF-16 offsets → derive TOC from chapters → save position as chapter index + local offset.

```
File bytes
  ↓ decode once (full file)
Full NSString
  ↓ regex once
Chapter[] (title, globalStartUTF16, textLengthUTF16)
  ├→ TOC display (derive TOCEntry from Chapter)
  ├→ Content loading (slice NSString by UTF-16 range)
  ├→ Navigation (direct chapter index)
  └→ Position save (chapter index + local UTF-16 offset)
```

## Constraints

- Must work for UTF-8, GBK, Big5, Shift_JIS, EUC-KR
- Files up to ~50MB (14MB GBK novel is the failing test case)
- Full-file decode is acceptable (~100ms for 14MB, same as existing full-text path)
- Must preserve existing test suite behavior for UTF-8 files
- Position save format must be backward-compatible (old locators still restore)
- Chapter index cache must be invalidated for old format

## Decision Log

| Decision | Options | Chosen | Rationale |
|----------|---------|--------|-----------|
| Chapter coordinate system | Byte offsets / UTF-16 offsets | **UTF-16 only** | Content loader slices decoded NSString; byte offsets are unused |
| Position save format | Global UTF-16 / chapter:local | **chapter:local in href** | Immune to offset drift; backward-compatible via fallback |
| Full-text decode timing | At service open / lazy on first load | **At service open** | Needed for chapter building anyway; avoids double decode |
| TOC source | Separate extraction / derived from chapters | **Derived from chapters** | Eliminates dual-system drift entirely |
| Cache format | Keep old / new format | **New format** | Old byte-offset caches are incompatible; auto-invalidate |

## Work Items

### WI-1: Rewrite chapter building — full-text decode + regex

**Goal**: Replace `TXTChapterIndexBuilder.buildWithRegex()` (streaming blocks) with a full-text regex pass that produces chapters with exact UTF-16 offsets.

**Acceptance**:
- Chapter titles match full-text regex exactly (no garbled GBK)
- `globalStartUTF16` values are exact (not estimated from byte ratios)
- `textLengthUTF16` values partition the full text without gaps
- Preamble chapter added if text before first match
- Falls back to synthetic ~50K chapters when <2 regex matches
- Existing tests pass (may need updating for new API)

**Tests first**:
- `TXTChapterIndexBuilderTests.swift` — update to test new full-text API
- Test: GBK text with known chapter positions → exact UTF-16 offsets
- Test: text with preamble → chapter 0 is "前言"
- Test: no regex matches → synthetic chapters
- Test: single match → synthetic chapters (need 2+)

**Touched areas**:
- `TXTService.swift:openChapterBased()` — replace streaming build with full-text build
- `TXTChapterIndex.swift` — byte offset fields become optional/unused
- `TXTChapterIndexBuilder.swift` — may be deleted or rewritten as thin wrapper

**Risks**: Full-text decode of 50MB file uses ~100MB memory (NSString). Mitigation: files >20MB fall back to streaming builder (existing code) with UTF-8-only guarantee.

---

### WI-2: Rewrite content loader — slice decoded string by UTF-16

**Goal**: Replace per-chunk byte-range decode with slicing the full decoded string by `globalStartUTF16` + `textLengthUTF16`.

**Acceptance**:
- Every chapter loads successfully for GBK, Big5, Shift_JIS files
- No `decodeFailed` errors for any chapter
- LRU cache still works (3-chapter window)
- `TXTLazyTextProvider` still works (uses content loader)

**Tests first**:
- `TXTChapterContentLoaderTests.swift` — update for new init (takes String, not Data+encoding)
- Test: load chapter from middle of GBK text → correct content
- Test: load last chapter → includes all remaining text
- Test: LRU eviction still works

**Touched areas**:
- `TXTChapterContentLoader.swift` — rewrite init to accept full decoded NSString
- `TXTService.swift` — pass decoded string to loader instead of raw data+encoding
- `TXTLazyTextProvider.swift` — may simplify (full text already available)

---

### WI-3: Derive TOC from chapter index

**Goal**: TOC entries are built from the chapter index, not from a separate full-text regex pass. One source of truth.

**Acceptance**:
- TOC entry titles exactly match chapter titles
- TOC entry UTF-16 offsets exactly match chapter `globalStartUTF16`
- No separate `TXTTocRuleEngine.extractTOC()` call for TOC display
- `activeEntryIndex` in TOCListView correctly highlights current chapter

**Tests first**:
- Test: TOC entries derived from 3-chapter index → titles and offsets match
- Test: preamble chapter included in TOC

**Touched areas**:
- `ReaderTOCBuilder.swift` — TXT path: build TOC from chapter index (not from full-text regex)
- `TXTReaderContainerView.swift` — pass chapter index to TOC builder
- `ReaderContainerView+Sheets.swift` — may need chapter index access

**Dependencies**: WI-1 (chapters must have correct titles and offsets)

---

### WI-4: Position save as chapter index + local offset

**Goal**: Save position as `txtchapter:{chapterIndex}:{localUTF16Offset}` in the Locator `href` field. Restore by parsing href directly — no global offset binary search.

**Acceptance**:
- Position saved includes `href: "txtchapter:N:M"`
- Position restored using href (chapter index + local offset)
- Backward-compatible: old locators without href fall back to global offset lookup
- Close → reopen lands on exact same chapter and scroll position
- Within-chapter scroll position restored via bridge's `restoreOffset`

**Tests first**:
- `TXTReaderViewModelTests.swift` — test makeLocator() includes href in chapter mode
- `TXTFileLoaderTests.swift` — test resolveChapterPosition parses href
- Test: href with valid chapter index → direct restore
- Test: href with out-of-bounds index → fallback to global offset
- Test: no href (legacy) → fallback to global offset

**Touched areas**:
- `TXTReaderViewModel.swift:makeLocator()` — add href encoding
- `TXTFileLoader.swift:resolveChapterPosition()` — add href parsing
- `TXTReaderContainerView.swift` — pass chapter-local offset to bridge's `restoreOffset`

**Dependencies**: WI-1 (chapters with correct UTF-16 offsets)

---

### WI-5: TOC navigation uses chapter index directly

**Goal**: When user taps a TOC entry, navigate by matching the entry to a chapter (by title or index), not by global UTF-16 offset.

**Acceptance**:
- TOC tap → correct chapter loaded
- Works for GBK, Big5 files
- Falls back to offset for non-TOC navigation (bookmarks, search)

**Tests first**:
- `TXTChapterIntegrationTests.swift` — test TOC title → chapter navigation
- Test: tap TOC entry → navigates to matching chapter by title
- Test: tap TOC entry with no title match → falls back to offset

**Touched areas**:
- `TXTReaderContainerView.swift:onNavigate` — title matching with fallback
- `TXTReaderViewModel.swift:navigateToChapterByTitle()` — return Bool for fallback

**Dependencies**: WI-3 (TOC derived from chapters, titles guaranteed to match)

---

### WI-6: Cache invalidation + cleanup

**Goal**: Invalidate old byte-offset-based caches. New caches store UTF-16-only chapter indices.

**Acceptance**:
- Old caches automatically invalidated on first open
- New caches persist correctly
- Cache hit path works for subsequent opens

**Tests first**:
- `TXTChapterIndexStoreTests.swift` — test cache with new format loads correctly
- Test: old cache (byte offsets, no UTF-16) → invalidated, rebuilt
- Test: new cache → loaded successfully

**Touched areas**:
- `TXTChapterIndexStore.swift` — may add version field for cache format
- `TXTService.swift` — cache validation logic

---

## Ordering

```
WI-1 (chapter building) → WI-2 (content loader) → WI-3 (TOC) → WI-4 (position) → WI-5 (navigation) → WI-6 (cache)
```

WI-1 and WI-2 are tightly coupled — chapter building determines how content is loaded.

## Files Deleted or Deprecated

| File | Action |
|------|--------|
| `TXTChapterIndexBuilder.buildWithRegex()` | Replaced by full-text builder in TXTService |
| `TXTOffsetTranslator.populateUTF16Offsets()` | No longer needed (offsets are exact from regex) |
| `TXTChapterContentLoader` byte-range decode | Replaced by NSString slicing |

`TXTChapterIndexBuilder.buildSynthetic()` may be kept for the fallback path.
`TXTOffsetTranslator.toLocal/toGlobal/chapterContaining` are still useful for highlight translation.

## Testing Procedures

```bash
# Unit tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:vreaderTests

# Build check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Manual Test Checklist

- [ ] Open GBK Chinese novel (《黑暗血时代》) — chapters detected, text readable
- [ ] TOC shows correct chapter titles (not garbled)
- [ ] Tap TOC entry → lands on correct chapter
- [ ] Read chapter 200, close, reopen → restores to chapter 200
- [ ] Scroll within chapter, close, reopen → restores to same scroll position
- [ ] Open UTF-8 TXT file → still works correctly
- [ ] Open file with no chapter headings → synthetic chapters work
- [ ] Open large file (>10MB) → acceptable load time (<2s)

## Plan → Verify Handoff

Per WI, collect:
- Unit test results (pass/fail)
- Manual test with GBK novel (chapter count, TOC correctness, position restore)
- Build output (no warnings from changed files)

Fixtures needed:
- Small GBK test file with known chapter positions (for unit tests)
- The user's GBK novel for manual testing
