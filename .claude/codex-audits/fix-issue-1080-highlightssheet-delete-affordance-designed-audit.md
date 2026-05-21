---
branch: fix/issue-1080-highlightssheet-delete-affordance-designed
threadId: 019e49ae-8329-7c30-976e-a073ac9a009d
rounds: 2
final_verdict: ship-as-is
date: 2026-05-21
---

# Codex Gate-4 audit — Bug #249 / GH #1080 (HighlightsSheet delete affordance)

Resolves the feature #62 WI-5 regression where the `AnnotationListView` (List +
`.onDelete`) → `HighlightsSheet` (`ScrollView` + `LazyVStack`) migration dropped
swipe-to-delete. Implements the **committed** design
`dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-delete.jsx`
(trailing `⋯` → `NotesActionMenu` Edit·Copy·Delete + inline confirm strip
mirroring `HPDeleteConfirm` + left-swipe drawer; container stays `LazyVStack`).

A prior `/fix-issue #1080` attempt (PR #1104) was correctly Gate-4-blocked
because no design existed (`.contextMenu` would have been self-invented chrome).
The design has since landed (HEAD `78c8986b`, resolves needs-design #1103), so
this implementation is design-faithful and rule 51 is satisfied. Codex was given
the design path explicitly and did **not** re-flag the affordance as a rule-51
violation — it confirmed the chrome matches the committed design.

## Round 1 — 4 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| `HighlightsSheet+Delete.swift:54` (`confirmDelete`) | **High** | Post-`await` `rowState` write was unconditional; if row A is deleting and the user opens/swipes row B before the delete returns, A's completion clobbers B's interaction. | **Fixed** — added an async-race guard: `guard rowState.activeRowId == id, rowState.phase == .deleting else { return }` before the post-await transition. The persistence remove still commits (record leaves the stream regardless); only the state write is suppressed. Tests `staleDeleteDoesNotClobberOtherRow` + `liveDeleteCompletionAllowed` added. |
| `HighlightsSheet+Delete.swift:94` (`edit`) | Medium | Edit is navigate-and-dismiss only; the design says Edit opens the editor after the jump. For highlights it's a partial (no programmatic `.readerHighlightTapped` entry point); for standalone notes `AnnotationEditSheet` is unwired. | **Accepted with follow-up** — Edit is documented as a navigate-to-passage handoff (the achievable behavior; auto-open requires cross-component plumbing out of scope for a delete-affordance fix). Follow-up filed at **GH #1121**. Test `editHighlightNavigatesAndDismisses` added. Round 2 confirmed this is sufficient for the #1080 slice "provided the follow-up is actually filed" — it is. |
| `HighlightAnnotationCard.swift:155` + `StandaloneNoteCard.swift:117` + `NotesDeleteRow.swift:79` | Medium | The card stayed tappable (jump) while the menu was open; the dismiss scrim was a `.background` (behind content), so an outside-tap-within-the-row navigated instead of dismissing. | **Fixed** — added `jumpEnabled: Bool` to both cards (taps route through `tryJump()`); `cardContent` sets `jumpEnabled: (phase == .default)` so jump is suppressed in every non-default phase. The `NotesDeleteRow` dismiss scrim moved to an `.overlay` ABOVE the card content but BELOW the menu, so a row tap dismisses while menu items stay tappable. |
| `NotesRowState.swift:115` (`dimAfterDelete`) | Low | `dimAfterDelete` + the design's 3s error auto-dismiss were defined/specified but unimplemented (success goes straight to `.dismissed()`; error persists). | **Fixed** — removed `dimAfterDelete` (the case, the `dimming(_:)` helper, `NotesDeleteRow`'s `isDim`/opacity, the test). Documented in `NotesRowState`'s header WHY: the VMs remove the record from their in-memory array as part of the delete, so on success the row leaves `currentStream` immediately — no row to dim without deferring persistence (out of scope). Error persists until manual Retry/Undo (intentional — the 3s auto-dismiss is a nicety; manual-only is safer and Undo/Retry are always present). |

## Round 2 — verification

**No new findings.** Codex confirmed: the High is resolved (guard prevents clobber,
allows normal completion; state-level tests match the production guard); both
Mediums adequately addressed (`jumpEnabled`/`tryJump` + scrim-as-overlay; Edit
honestly documented + tested as navigate-and-dismiss with the follow-up filed);
the Low removal is sound (state machine now matches the real data flow).

Residual note (not a finding): the async-race tests are model-level (validate the
guard logic, not the full async `confirmDelete`) — a testing-completeness note,
accepted: `confirmDelete` is a SwiftUI `@State`-mutating method on a `View` (not
observable outside a render tree), so an end-to-end async exercise would require a
UI-host harness; the guard logic itself is the load-bearing part and is covered.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium findings. The Medium-Edit is
accepted-with-follow-up (#1121); the implementation is faithful to the committed
design and does not invent UI. 50 targeted tests pass
(`NotesRowStateTests` + `HighlightsSheetDeleteTests` + `HighlightsSheetTests` +
`HighlightAnnotationCardTests`, `-parallel-testing-enabled NO`, UDID
`61149F0E-DC18-4BE2-BB37-52659F1F4F62`).
