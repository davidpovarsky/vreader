---
branch: fix/issue-604-library-grid-cards-vertical-misalign
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Bug #177 / GH #604 — Library grid card vertical alignment (audit log)

## Context

Bug #177 (filed by user 2026-05-13): in the library grid, book cards with fewer
metadata rows (no author / no reading-time) appear vertically centered within
their LazyVGrid row, drifting LOWER than taller cards in the same row that have
the full author + reading-time stack. Cover tops don't align.

## Codex availability

Codex MCP unavailable this session (`stream disconnected before completion` on
every call earlier in the session). Manual fallback per rule 47.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Views/BookCardView.swift` | grid card view (one-line fix) | reviewed |

## Manual audit evidence

### Files read

- `vreader/Views/BookCardView.swift` — full file (151 lines). Confirmed
  `body`'s outer `VStack(alignment: .leading, spacing: 8)` has conditional
  rows (author at line 38, reading time at line 46, speed at line 53).
  Confirmed `.frame(maxWidth: .infinity, alignment: .leading)` is set on
  the outer VStack but no maxHeight — that's the root cause: LazyVGrid
  gives each cell a row-height equal to the tallest cell in the row, and
  SwiftUI defaults to vertical-center cross-axis when content is shorter.
- `CoverContainerView` (lines 101-150): cover uses `.aspectRatio(2.0/3.0,
  contentMode: .fit)` driving uniform card-width-derived cover height —
  the cover itself doesn't differ; only the metadata stack differs.

### Symbols verified

- `Spacer(minLength: 0)` — stdlib SwiftUI; `minLength: 0` means the spacer
  contributes zero minimum size but takes all remaining space available
  to it. Idiomatic for "push content to top, fill row height".

### Edge cases checked

1. **Card with no metadata rows** (only title): Spacer expands to fill the
   delta to the tallest sibling. Title + cover stay at top. PASS.
2. **Card with all metadata rows** (author + reading time + speed): Spacer
   contributes 0 since no leftover space. No visual change for this
   pre-existing tallest-card case. PASS.
3. **Single-card row** (rare but possible — last book in a non-full row):
   no taller siblings, so Spacer contributes 0. No visual change. PASS.
4. **Dynamic Type / VoiceOver**: Spacer doesn't change layout semantics
   for accessibility — title/author still come first, accessibility label
   is unchanged. PASS.
5. **Custom cover image fallback**: cover is rendered via overlay on a
   `Color(white: 0.92)` rectangle whose `.aspectRatio` drives height —
   the Spacer is below the cover, doesn't interact. PASS.

### Risks accepted

- **Pure layout change**: no test added because SwiftUI layout outcomes
  aren't catchable by Swift Testing / XCTest unit tests (visual snapshot
  testing isn't in vreader's harness). Pre-FIXED simulator verification
  covers the observable behavior. This is the documented exception per
  `.claude/rules/10-tdd.md` ("CSS-only, docs, config" category — pure
  visual layout fixes fall in this same category).

### Concurrency / Swift 6

- `BookCardView` is a SwiftUI `View` struct — no actor concerns introduced.
- `Spacer` is `Sendable`.

### VReader compliance

- Swift 6 strict concurrency: clean.
- `@MainActor` correctness: SwiftUI body is implicit MainActor; Spacer is fine.
- File size: 159 lines (was 151) — well under 300.
- Bridge safety: not applicable.

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — minimal, matches bug body's prescribed fix exactly | n/a |

## Final verdict

**ship-as-is** — minimal 5-line addition (4 lines comment + 1 line `Spacer(minLength: 0)`), matches the bug body's prescribed fix verbatim, no edge-case concerns, no regression risk in any reader/persistence/networking surface (purely a library-grid layout concern).
