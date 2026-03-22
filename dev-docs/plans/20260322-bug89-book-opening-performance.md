# Bug #89 — Book Opening Performance (Legado-Style Lazy Loading)

**Bug #89** | **GH: #16** | **Severity**: Critical | **Date**: 2026-03-22

## Problem

VReader takes 5-25s to open because it decodes the ENTIRE file before showing content. Legado opens instantly by loading only the current chapter (~5KB).

## 10 Work Items

| WI | Goal | Size | Dependencies |
|----|------|------|-------------|
| **1** | TXT streaming chapter index builder (512KB blocks, byte offsets) | M | None |
| **2** | TXT lazy chapter content loader (3-chapter LRU cache) | S | WI-1 |
| **3** | Chapter index persistence (JSON file, invalidate on mod date) | S | WI-1 |
| **4** | UTF-16 offset translation layer (global ↔ chapter-local) | S | WI-1 |
| **5** | Integrate into TXTService + ViewModel (replace full-file decode) | L | WI-1-4 |
| **6** | Chapter-based display in container view | L | WI-5 |
| **7** | Highlight/search/bookmark offset translation | M | WI-4-6 |
| **8** | EPUB pre-extraction on import (independent) | S | None |
| **9** | AI/Search/TTS lazy full-text loading | S | WI-5 |
| **10** | Performance verification + architecture doc update | S | All |

## Key Design Decisions

- **D1**: Chapters stored as byte offset pairs `(startByte, endByte)` — Legado pattern
- **D2**: Chapter index persisted to JSON file (avoids SwiftData schema change)
- **D3**: 3-chapter sliding window (prev/cur/next) — Legado pattern
- **D4**: Global UTF-16 offsets remain the public API; translation at container boundary
- **D5**: No-chapter-match fallback: synthetic 50KB chapters at paragraph breaks
- **D6**: EPUB pre-extracted on import; existing on-demand fallback preserved
- **D7**: Full text loaded lazily only when AI/search/TTS needs it

## Performance Targets

| File | Current | Target |
|------|---------|--------|
| Small TXT (100KB) | 1-3s | < 200ms |
| Medium TXT (1MB CJK) | 5-10s | < 500ms |
| Large TXT (15MB CJK) | 15-25s | < 1s |
| EPUB (10MB, cached) | 2-5s | < 300ms |
| EPUB (10MB, cold) | 5-15s | < 2s |

## Implementation Order

```
WI-1 → WI-2 → WI-3 → WI-4 → WI-5 → WI-6 → WI-7 → WI-9 → WI-10
                                                WI-8 (parallel, independent)
```

WI-1 through WI-4 are pure logic — ideal for parallel TDD agents.

Full details: see planner agent output in session transcript.
