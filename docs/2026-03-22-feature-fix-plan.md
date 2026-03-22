# Feature Fix Plan (Revised)

All TODO features — prioritized by effort, dependency, and risk.

## Phase 0 — Discovery (before any fixes)

Reproduce and write RED tests for uncertain bugs. Do NOT implement fixes yet.

| Bug | Feature | Task |
|-----|---------|------|
| #77 | #11 EPUB highlights | Repro on device: select text in EPUB, observe if selectionChanged fires. Write failing test |
| #82 | #21 Paged mode | Repro per format: TXT small, TXT large, EPUB, PDF. Identify which formats actually fail |
| #98 | #27/#28 Transforms | Repro: add replacement rule, toggle simp/trad. Determine crash vs silent no-op |

**Acceptance**: Each bug has a confirmed root cause and a failing test.

## Phase 1 — Verify & Close (bugs already fixed, verify on device)

| # | Feature | Blocking Bug | Remaining Bugs | Verify |
|---|---------|-------------|----------------|--------|
| 13 | AI summarize | #92 FIXED | None | Open non-UTF-8 TXT → AI summarize → shows real content |
| 18 | AI translate | #95 FIXED | None | Select word → Translate → opens Translate tab |
| 24 | Book sources | #100, #101 FIXED | None | Import JSON → sources visible → search works |

**NOT ready to verify** (still have open bugs):
- #26 TTS: #96 fixed but #97 (bar overlap) still open → stays in Phase 2
- #35 Export/import: #88 (imported highlights don't render) still open → stays in Phase 2

## Phase 2 — Bug Fixes (code exists, specific bugs)

### Priority order:

**Quick fixes:**
| Bug | Feature | Root Cause | Fix |
|-----|---------|-----------|-----|
| #97 | #26 TTS | TTSControlBar overlaps bottom bar | Fix z-order/spacing |
| #85 | #34 Collections | No "Add to Collection" in context menu | Add context menu action |
| #86 | #34 Collections | allTags:[] hardcoded | Load tags from PersistenceActor |
| #84 | #37 Per-book | resolve() never called | Wire into ReaderSettingsStore on book open |

**Moderate fixes (after discovery):**
| Bug | Feature | Fix (pending repro) |
|-----|---------|-----|
| #77 | #11 EPUB highlights | Depends on discovery — likely JS selection fallback |
| #82 | #21 Paged mode | Depends on discovery — per-format diagnosis needed |
| #98 | #27/#28 Transforms | Depends on discovery |
| #88 | #35 Export/import | Extend export format with locator data; trigger restoreAll after import |
| #83 | #23 TXT TOC | Broaden rule patterns after analyzing failing files |
| #31 auto page turn blocked by #82 |

**Execution order:**
```
#97 → #85/#86 → #84 → (discovery results) → #77 → #98 → #88 → #82 → #83 → #31
```

## Phase 3 — Device Verification (no known bugs, just needs testing)

| # | Feature | Pass Criteria |
|---|---------|--------------|
| 5 | Search auto-dismiss | Search highlight clears on scroll, tap, or new search |
| 29 | WebDAV backup | Backup creates archive; restore recovers data. Test with real WebDAV server |
| 36 | OPDS catalog | Add catalog URL, browse, download book → appears in library |

## Phase 4 — New Implementation (requires PLANNED status first)

Each feature must have Problem/Scope/Edge Cases/Test Plan/Acceptance Criteria in features.md before implementation.

**Small:**
| # | Feature | Scope |
|---|---------|-------|
| 25 | Tap zone settings UI | TapZoneSettingsView in ReaderSettingsPanel. Picker for left/center/right actions |
| 32 | Theme bg image picker | PhotosPicker in ReaderSettingsPanel. Wire to ThemeBackgroundStore.saveBackground() |

**Medium (TXT/MD only first — not cross-format):**
| # | Feature | Scope |
|---|---------|-------|
| 40 | TTS sentence highlight | AVSpeechSynthesizerDelegate willSpeakRange → highlight in TXT/MD only. EPUB/PDF deferred |
| 41 | TTS auto-scroll | Use TTS UTF-16 offset to scroll TXT/MD. EPUB/PDF deferred |

**Large (architecture spike first):**
| # | Feature | Scope |
|---|---------|-------|
| 10 | iCloud backup | Spike: validate if BackupProvider abstraction fits CloudKit. If not, separate sync service. Then implement |

## Rules

- Read `docs/architecture.md` before each phase
- Unit tests only: `xcodebuild test -only-testing:vreaderTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Discovery before fix for uncertain bugs (#77, #82, #98)
- Features must reach PLANNED before IN PROGRESS (Phase 4)
- Update `docs/architecture.md` after architectural changes
- Update `docs/manual-test-checklist.md` with verification items
- Codex audit after each phase
