---
branch: triage/bug-180-rescope-continuous-scroll
bug: 180
date: 2026-05-16
final_verdict: ship-as-is
---

## Scope

Docs-only triage refinement: re-scopes Bug #180 in `docs/bugs.md` per a 2026-05-16 user directive. No Swift source changes. No test changes.

The user rejected the discrete chapter-SWAP approach (PR #681) outright and specified the desired behavior: TXT scroll mode must scroll **continuously, smoothly, endlessly** across chapter boundaries with no jump. Two tracking decisions captured from the user:
1. Keep the work under bug #180 (re-scope the bug; do NOT split a separate feature).
2. Chapter awareness must be preserved under continuous scroll (TOC jumps, per-chapter progress, feature #48 chapter-scoped highlight pipeline).

## Audit

No logic to audit. The re-scoped fix direction is grounded in code-read evidence already gathered in the prior triage (`triage-bug-180-reopened-scroll-boundary-cascade-audit.md`) plus:

- Existing continuous renderers confirmed present: flat-mode `UITextView` (whole small file) and `TXTChunkedReaderBridge` (chunked `UITableView` for >500K UTF-16 — already lazy-windows rows). The re-scoped fix builds on the chunked windowing rather than introducing a new infinite-scroll engine.
- `TXTReaderViewModel.currentChapterIdx` is currently a render-mode switch (chapter mode loads one chapter at a time). The re-scope makes it a *derived* value from scroll offset — this is the central architecture change and is documented as the fix direction, not implemented here.
- Feature #48 (chapter-scoped highlight pipeline, VERIFIED) depends on global↔chapter-local UTF-16 offset translation; the re-scoped fix must keep that mapping working over the continuous surface. Documented as a hard constraint.
- Feature #60 design bundle is paginated — no continuous-scroll chrome is designed. The entry documents that behavior-only continuous scroll reusing existing chrome is fine, but any *new* scroll-mode UI surface (e.g. a v2-styled scroll/paged toggle, chapter dividers) is undesigned and falls under rule 51 → file `Design needed:` if required.

## Tracking-decision note

The user explicitly chose to carry feature-sized work on a bug row. The entry documents this: bug #180 skips the `/feature-workflow` gates (it is a bug, not a feature), but the fix still warrants a written plan given the architecture surface (continuous-scroll rendering + derived chapter index + windowing). This is a deliberate, recorded deviation — not an oversight.

## Verdict

ship-as-is — documentation only, no code risk. Bug #180 stays `REOPENED` with a re-scoped fix direction. The fix follows on its own PR.
