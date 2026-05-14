---
branch: triage/bug-189-azw3-ignores-scroll-mode-toggle
bug: 189
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Bug #189 row + detail entry to `docs/bugs.md` for the AZW3/MOBI half of the user's two-part report. The TXT/EPUB half is a duplicate of bugs #180 (TXT) and #165 (EPUB) — both already TODO with GH issues — so no new tracker entry was filed for that half. No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:

- `vreader/Views/Reader/FoliateReaderContainerView.swift:189`: literal `layoutFlow: "paginated"` passed to the bridge constructor. Confirmed by direct read of lines 180–204.
- `vreader/Views/Reader/FoliateViewBridge.swift:46-47, 232-238`: `layoutFlow: String = "paginated"` default; `updateUIView` reads the value via `FoliateJSEscaper.sanitizeFlow(layoutFlow)` and pushes `readerAPI.setLayout({flow: '<safeFlow>'})` via `evaluateJavaScript`. Header comment (line 10) explicitly states "updateUIView detects themeCSS and layoutFlow changes" — so live-toggle works once the binding is correct.
- `vreader/Services/Foliate/FoliateJSEscaper.swift:87-95`: `sanitizeFlow` switch accepts `"paginated"` and `"scrolled"`; defaults to `"paginated"` for any other input.
- `vreader/Services/Foliate/FoliateStyleMapper.swift:63-81`: `layoutJS(flow:margin:maxInlineSize:maxColumnCount:)` emits the corresponding `setLayout({flow: ..., margin: ..., ...})` call.
- `vreader/Views/Reader/TXTReaderContainerView.swift:757-759`: `isPagedMode = settingsStore?.epubLayout == .paged && !isLargeFile` — TXT consults `epubLayout`.
- `vreader/Views/Reader/EPUBReaderContainerView.swift:63`: `isPaged` mirror — EPUB consults `epubLayout`.
- Foliate-js itself supports both modes: `vreader/Services/Foliate/JS/foliate-bundle.js:4393` `this.#column = layout.flow !== "scrolled";` — so Foliate honors `"scrolled"` by disabling column layout.

**User's report had two parts; this triage covers only the AZW3 half**:
1. Part 1 — TXT + EPUB scroll mode lacks scroll-driven chapter navigation. Already tracked as bug #180 (TXT, GH #614) and bug #165 (EPUB, GH #489). No new bug needed.
2. Part 2 — AZW3 ignores the scroll/paged toggle entirely. This is bug #189 (new).

Severity: Medium. Foliate-rendered formats (AZW3 + MOBI + PRC + AZW per `FormatCapabilities`) are stuck on paginated regardless of the user's reading-mode preference. Workaround: none in production.

## Verdict

ship-as-is — documentation only, no code risk.
