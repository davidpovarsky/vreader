# Feature #43: Cover Image Extraction (EPUB + AZW3)

**GH:** #121 | **Status:** PLANNED | **Date:** 2026-04-03

## Problem

EPUB and AZW3 books show format placeholder icons instead of actual cover images in the library. The display infrastructure exists (~40%) but the extraction layer is missing.

## Scope

Extract cover images from EPUB and AZW3 files at import time, save them via CustomCoverStore, and display them in the library.

## Key Design Decisions

### D1: Cover ownership boundary
- **Parser** finds the cover reference (href/offset)
- **Extractor** reads bytes and returns `UIImage?` (no disk I/O)
- **BookImporter** owns `CustomCoverStore.saveCover()` — single place for persistence and rollback

### D2: `coverImagePath` is unused
The UI loads covers via `CustomCoverStore.loadCover(for: fingerprintKey)`, never via `Book.coverImagePath`. We won't populate `coverImagePath` — just save to `CustomCoverStore`. The field stays nil (legacy).

### D3: Extracted vs custom cover precedence
- Import saves extracted cover to `CustomCoverStore` (same store as user covers)
- User cover overrides extracted cover (same key, last write wins)
- "Remove Cover" deletes the file — no auto-restore of extracted cover
- Re-import of same book: if `CustomCoverStore.hasCover()` → skip extraction (preserves user override)

### D4: Inline extraction (not fire-and-forget)
Cover extraction runs synchronously during import. EPUB ZIP read is fast (<50ms for a single image). This ensures the cover is visible immediately in the library.

## Existing Infrastructure

| Component | Status | Location |
|-----------|--------|----------|
| `CustomCoverStore` | Fully working (save/load/remove) | `Services/CustomCoverStore.swift` |
| `BookCardView`/`BookRowView` | Check CustomCoverStore, fallback to icon | `Views/BookCardView.swift:86` |
| `EPUBParser` + `ZIPReader` | Parse OPF, extract ZIP entries | `Services/EPUB/` |
| Foliate-js `getCover()` | Works for MOBI/EPUB in JS | `Services/Foliate/JS/mobi.js:633` |
| `MetadataExtractor` protocol | Returns `BookMetadata` with optional cover | `Services/MetadataExtractor.swift` |

## Work Items

### WI-0: Cover lifecycle — cleanup on delete + rollback on import failure

**What:** Wire cover file cleanup into book deletion and import rollback paths.

**Details:**
1. In `PersistenceActor.deleteBook()` (or its caller in LibraryView), call `CustomCoverStore.removeCover(for: fingerprintKey)` before/after DB deletion
2. In `BookImporter.importFile()`, if persistence fails after cover was saved, remove the orphan cover file in the catch block
3. On duplicate import: if `CustomCoverStore.hasCover(for:)` → skip cover extraction (preserves user overrides)

**Files:** `LibraryView.swift` (delete action), `BookImporter.swift` (rollback), `PersistenceActor+Library.swift`

**Tests:**
- Delete book → `CustomCoverStore.hasCover()` returns false
- Import fails after cover saved → cover file cleaned up
- Duplicate import with existing cover → cover not overwritten

**Acceptance:** No orphan cover files after delete or failed import.

---

### WI-1: EPUBParser — extract cover image reference from OPF

**What:** Enhance `OPFXMLDelegate` to capture cover image href from OPF metadata.

**Details:**
- EPUB 2: `<meta name="cover" content="cover-image-id"/>` → look up ID in `manifest` dict → get href
- EPUB 3: `<item properties="cover-image" href="..."/>` → direct href
- Add `coverImageHref: String?` to `EPUBMetadata` struct
- Resolve href: strip fragment (`#...`), percent-decode, join with OPF directory path
- `guide` element cover refs: out of scope (rare, can add later)

**Path resolution example:**
- OPF at `OEBPS/content.opf`, cover href `Images/cover.jpg` → archive path `OEBPS/Images/cover.jpg`
- href `../cover.jpg` → archive path `cover.jpg`
- href `cover.jpg#fragment` → strip to `cover.jpg`, then resolve

**Files:** `EPUBParser.swift` (OPFXMLDelegate ~line 371), `EPUBTypes.swift` (EPUBMetadata ~line 26)

**Tests:**
- EPUB2-style `<meta name="cover">` → extracts correct archive path
- EPUB3-style `properties="cover-image"` → extracts correct archive path
- No cover in OPF → returns nil
- Cover ID in meta but missing from manifest → returns nil
- Href with fragment → stripped correctly
- Relative path with `../` → resolved correctly

**Acceptance:** `EPUBParser.open(url:)` returns `coverImageHref` (archive-relative path) for EPUBs that have covers.

---

### WI-2: EPUBMetadataExtractor — extract cover image bytes

**What:** Replace the stub extractor with real implementation. Extractor returns `UIImage?`, importer saves it.

**Details:**
1. Change `MetadataExtractor` protocol: add `extractCoverImage(from:) -> UIImage?` (optional, default nil)
2. `EPUBMetadataExtractor.extractMetadata()`: use lightweight OPF-only parsing (not full `EPUBParser.open()`) to get title, author, coverImageHref
3. `EPUBMetadataExtractor.extractCoverImage()`:
   - Open ZIP via `ZIPReader(url:)`
   - Find entry via `zipReader.entry(forPath: coverImageHref)`
   - Extract data via `zipReader.extractData(for: entry)`
   - Return `UIImage(data: imageData)` (nil if corrupt/unsupported)
4. In `BookImporter.importFile()`, after metadata extraction:
   - Call `extractor.extractCoverImage(from: sandboxURL)`
   - If image returned AND `!CustomCoverStore.hasCover(for: fingerprintKey)`: save it
   - If persistence later fails: clean up (WI-0)

**Supported image formats:** JPEG, PNG, GIF (via `UIImage(data:)`). SVG → skip.

**Files:** `MetadataExtractor.swift`, `BookImporter.swift` (~line 165)

**Tests:**
- Valid EPUB with JPEG cover → extractor returns UIImage
- EPUB without cover → returns nil
- Corrupt image data → returns nil, no crash
- SVG cover → returns nil (UIImage can't decode SVG)
- Integration: import EPUB → `CustomCoverStore.hasCover()` returns true

**Acceptance:** Importing an EPUB with a cover image saves it and shows it in the library.

---

### WI-3: AZW3 cover extraction via native MOBI header parsing

**What:** Parse MOBI/PDB header + EXTH records natively in Swift to extract cover image.

**Why native:** WKWebView at import time is heavyweight and unreliable in background.

**Supported subset (first pass):**
- PDB header → record count + offsets (first 78 bytes + record table)
- MOBI header → EXTH flag (bit 6 of mobi flags at offset 128)
- EXTH records → type 201 (coverOffset) or 202 (thumbnailOffset)
- First image record index from MOBI header (offset 108, 4 bytes big-endian)
- Image at record `firstImageRecord + coverOffset`

**Explicitly deferred:**
- KF8-only containers (no MOBI7 header) — defer to Feature #42
- DRM-protected files — skip gracefully
- Files without EXTH — return nil

**Files:** New `Services/AZW3/MOBICoverExtractor.swift`, `MetadataExtractor.swift`

**Tests (with binary fixture data):**
- AZW3 with EXTH cover offset → extracts JPEG image
- MOBI without EXTH flag → returns nil
- Cover offset 0xFFFFFFFF → returns nil
- Truncated file → returns nil, no crash
- Integration: import AZW3 → cover shows in library

**Acceptance:** Importing a standard AZW3 with a cover shows it in the library. DRM/exotic formats fail gracefully.

---

### WI-4: End-to-end verification + test gate

**What:** Integration tests + visual verification.

**Details:**
- Unit tests for all WIs run green
- Import EPUB with cover → visible in grid and list views
- Import AZW3 with cover → visible in grid and list views
- Delete book → cover file removed
- Re-import same book (cover already exists) → cover preserved
- Import book without cover → placeholder icon shown

**Files:** Test files + visual QA via Simulator

**Acceptance:** All tests pass. Visual QA confirms covers display correctly.

## Risks

| Risk | Mitigation |
|------|------------|
| WI-3 (MOBI parsing) too fragile | Ship EPUB (WI-0/1/2) first. Gate AZW3 behind fixture availability. Defer exotic formats to #42. |
| Large cover images | CustomCoverStore resizes to 512x512 max |
| Import latency | EPUB ZIP read <50ms. MOBI header read <10ms. Both inline. |
| Orphan cover files | WI-0 handles cleanup on delete and rollback |

## Order

WI-0 → WI-1 → WI-2 → WI-4(EPUB) → WI-3 → WI-4(full)

Ship EPUB covers first (WI-0/1/2), then add AZW3 (WI-3).
