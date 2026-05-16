---
branch: docs/feature-60-wi-1b-deferral
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-16
---

## Scope

Records the deferral of feature #60 WI-1b in the implementation plan. Touches `dev-docs/plans/20260515-feature-60-visual-identity-v2.md` (WI table — WI-1 split into WI-1a/WI-1b rows; revision-history v8 entry) + `project.yml` / `project.pbxproj` (version bump 3.24.1/396 → 3.24.2/397).

**No Swift source files changed.** The audit-gate hook fires because `project.pbxproj` is in the diff — false positive of the Swift-file heuristic. Manual mini-audit.

## Manual audit evidence

### What changed and why

- WI-1 (originally one foundational WI: `ReaderTypography` registry + `ReaderFontFamily` cases + bundled `.otf` binaries + `UIAppFonts`) is split:
  - **WI-1a** — registry + enum cases. Pure code, dormant infra, cron-implementable.
  - **WI-1b** — vendoring the actual Source Serif 4 + Inter `.otf` binaries + `UIAppFonts` registration. **Deferred** per a 2026-05-16 user directive: it requires fetching external font assets and verifying their licenses (both SIL OFL — the OFL text must be vendored + the verification recorded), which a cron iteration cannot safely do.
- A GH issue (#774) tracks WI-1b as a manual-ops task with the downstream-gate impact documented.

### Correctness checks

1. **Downstream gate is accurate** — until WI-1b lands, `ReaderTypography.body(for:)` falls back to system fonts on device (the plan's own edge-case #2 confirms this fallback exists). So WI-5's Gate 5a typography device-verify, the Foliate font-bundling slice (Risk (c)), and the Gate 5b final acceptance pass genuinely cannot confirm "Source Serif 4 renders" until WI-1b. The plan now states this gate explicitly — this is a real correctness improvement (it prevents a false "typography verified" claim).
2. **GH issue number** — issue created as #774; both the WI-1b table row and the v8 revision-history entry cite #774 (initial draft said #772 before the issue was created; corrected after).
3. **No scope creep** — the edit is confined to recording the deferral. No WI was implemented; no font binary was fetched (that IS WI-1b).
4. **Version bump** — 3.24.2 / build 397 (patch — plan-doc + tracking change, no user-visible behavior). xcodegen regen confirmed.

### Risks accepted

None. Documentation-only. The deferral itself is the user's decision; this PR records it.

## Verdict

ship-as-is — plan revision + version bump. No Swift logic. Manual fallback used because there is nothing to send to Codex.
