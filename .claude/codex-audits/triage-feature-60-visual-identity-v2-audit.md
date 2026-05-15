---
branch: triage/feature-60-visual-identity-v2
feature: 60
date: 2026-05-15
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit. Files Feature #60 (visual identity v2) into `docs/features.md` and commits the full claude.ai/design handoff bundle to `dev-docs/designs/vreader-fidelity-v1/` so any agent on any Mac can read the design offline (no dependency on the Anthropic share endpoint). Adds `Cross-ref: #60` notes to Feature #53 and Feature #55 rows. No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in:

**Design bundle evidence** (committed under `dev-docs/designs/vreader-fidelity-v1/`):
- `README.md` — claude.ai/design handoff instructions ("CODING AGENTS: READ THIS FIRST").
- `chats/chat1.md` — 446-line intent + iteration log showing the user's design choices: scope=explore-options, platform=iPhone-only, themes=light/sepia/dark/OLED/photo, interactivity=fully-interactive, content=fiction+nonfiction+technical.
- `project/VReader Prototype.html` — entry point. 169-line single-file React/Babel prototype. iPhone device frame with Dynamic Island + home indicator.
- `project/vreader-app.jsx` — App shell. Routes between Library and Reader. Owns `readerSettings: {theme, fontFamily, fontSize, lineHeight, margin, brightness}`, `openSheet` state, status-bar tinting via `theme.isDark`.
- `project/vreader-themes.jsx` — 5 themes (paper / sepia / dark / oled / image). Each carries `bg`, `paper`, `ink`, `sub`, `rule`, `accent`, `chrome`, `isDark`, `paperPattern`. Accent: `#8c2f2f` (paper), `#7a3a1f` (sepia), `#d6885a` (dark/oled), `#e8b465` (image).
- `project/vreader-library.jsx` — `LibraryScreen` with ContinueCard rail + GridView/ListView toggle, filter pillBtn.
- `project/vreader-reader.jsx` — `ReaderScreen`, `PageContent`, `Paragraph`, `Segments`, `buildSegments`, `ReaderTopChrome`, `ReaderBottomChrome`, `SelectionPopover` (lines 438-495).
- `project/vreader-panels.jsx` — `Sheet`, `ReaderSettingsSheet`, `TOCSheet`, `HighlightsSheet`, `AISheet` with `SummaryView`, `ChatView`, `TranslateView`, `SettingsSheet`.
- `project/vreader-icons.jsx`, `vreader-cover.jsx`, `vreader-data.jsx`, `ios-frame.jsx` — supporting components.
- `project/screenshots/` — 31 PNG screenshots (~700KB) covering Library, Reader chrome, AI panel tabs, Reader Settings, Dark theme, Photo theme.

**Scope cross-checks against existing tracker state**:
- `SelectionPopover` (vreader-reader.jsx:438-495): handles new-selection-from-long-press only. 4 colors (yellow/pink/green/blue) + Note / Translate / Ask AI / Read. Does NOT cover tap-on-existing-highlight (#53 territory) or tap-on-annotated-text (#55 territory). Confirmed by reading the function in full — no `existingHighlight`/`existingAnnotation` props, no hit-test entry path; called only from `onLongPress` in `Paragraph`.
- `#53` status verified: IN PROGRESS, WI-1 merged 2026-05-15 in v3.22.5 (commit 7f29efe, PR #706). Foundational infra (`.readerHighlightTapped` notification + `HighlightActionPresenting` protocol + `HighlightTapAction` enum + coordinator handler) is chrome-agnostic. NOT marked DUPLICATE.
- `#55` status verified: TODO, no WIs shipped, no plan. NOT marked DUPLICATE — design has no UI for tap-on-annotated-text state.
- Out-of-design surfaces verified absent: PDF chrome, AZW3/MOBI chrome, search results panel, WebDAV restore picker UI, AI provider editor, #58 dashboard, #38 TOC tree, #56 bilingual inline mode. Each documented in the scope row as "out of scope for v1".

**Cross-ref edits**:
- #53 row: appended `**Cross-ref**: Feature #60 (visual identity v2) — distinct flow (tap-on-existing-highlight vs new-selection-from-long-press). #53's foundational infra is chrome-agnostic; WI-2..6 presenters may be re-skinned post-#60.`
- #55 row: appended `**Cross-ref**: Feature #60 (visual identity v2) — the design's SelectionPopover does NOT cover tap-on-annotated-text; #55 remains a distinct hit-test + presenter flow whose presenter may be re-skinned post-#60.`
- No status changes for #53 or #55.

**Cross-Mac portability**: bundle is committed (812K, ~700K of which is the screenshots dir). Any Mac with `git pull` gets the full design offline; no dependency on `api.anthropic.com/v1/design/h/...` staying up or on `WebFetch` being able to decode the gzipped tar payload (which it can't — confirmed earlier this session when the WebFetch returned the bundle as a `.bin` file requiring manual `tar xzf`).

## Verdict

ship-as-is — documentation + design-bundle only, no code risk. Implementation goes through `/feature-workflow` (Gates 1–6) once the user opens it. The bundle is ready for offline read by any Claude Code session on any Mac.
