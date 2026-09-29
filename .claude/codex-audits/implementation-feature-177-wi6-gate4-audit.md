# Feature #177 WI-6 — Gate 4 implementation audit

Date: 2026-09-29
Baseline: `43eccdafdde92c4b96427e189c8c0f7ef073104b`
Mode: manual fallback after independent auditors were unavailable (`codex exec`:
Windows access denied; Claude Code and OpenCode: insufficient account funds).

## Round 1 — REVISE

Findings:

1. High: an exact overlap's read-ahead probe advanced only its global coordinate,
   leaving the earlier local coordinate authoritative in `AIReadingBoundaryPolicy`
   and allowing an unread suffix without confirmation.
2. High: the first open-book ready bridge consumed a global position notification;
   a concurrent reader of the same fingerprint could trigger target delivery before
   the intended reader was ready.
3. Medium: the initial test catalogue did not directly exercise all specified
   `get_book_content`, format-fallback, other-book Ask/Allow, and same-fingerprint
   search/navigation paths.
4. Medium: the overlap coordinator switched directly on persisted read-ahead mode
   instead of letting the central execution gate/policy resolve the unread probe.

Disposition:

- Advanced both exact local and global probe coordinates and added approval/denial
  overlap coverage.
- Bound pending target delivery to a newly claimed `readerToken`, the exact
  `AIDocumentSessionID`, and that session's provider-attach notification.
- Expanded the focused catalogue to 67 tests across 13 suites, including direct
  FTS, structured content authority, format fallback, cancellation, ready-seam,
  and concurrent-reader integration tests.
- Removed direct read-ahead-mode inspection; the boundary helper now asks
  `AIAgentToolExecutionGate`, which delegates to `AIToolAuthorizationPolicy`.

## Round 2 — APPROVE

No open Critical, High, or Medium findings remained in the manual re-review.

### Manual Audit Evidence

Files read:

- All changed files in `vreader/Services/AI/Tools/` and reader/library call sites.
- All new files in `vreader/Features/AIAgent/Tools/` and
  `vreader/Features/AIAgent/Retrieval/`.
- All WI-6 focused tests in `vreaderTests/Features/AIAgent/Tools/`.
- WI-3/WI-4 provider registry, document models/providers/context resolver,
  WI-5 policy/preferences/broker/bridge, annotation persistence protocols, and
  reader notification/navigation routes.

Symbols and signatures verified:

- `AITool.run(_:) async -> ToolResult`, `AIDocumentSessionID`,
  `AIDocumentProviderRegistry.resolve(session:)`, `AIDocumentChunk`,
  `AIReadSoFarBoundary`, `AIReadingBoundaryPolicy.evaluate`,
  `AIToolAuthorizationPolicy.authorize/authorizeReadAhead`,
  `AIActionConfirmationBroker.requestConfirmation`, annotation read protocols,
  `Notification.Name.readerNavigateToLocator`, and production registry construction.

Edge cases checked:

- Allow/Ask/Deny/unavailable confirmation and task cancellation.
- Exact UTF-16 overlap including a surrogate pair; behind, ahead, and unknown order.
- PDF page, EPUB href, TXT/Markdown, and bounded legacy behavior.
- Huge `start_char`, closed-book extraction bypass, bounded outputs, empty input,
  wrong fingerprint, remote/unreadable book, duplicate confirmation resolution,
  same-fingerprint reader tokens, and one-shot ready navigation.
- New and materially changed WI-6 files remain below 300 lines.

Risks accepted:

- Production confirmation presentation is intentionally absent in WI-6; the
  production gate reports approval unavailable without enqueueing a request.
- EPUB with no provable intra-resource text boundary fails closed under Never;
  whole-book permission or an approved Ask is required for that resource body.
