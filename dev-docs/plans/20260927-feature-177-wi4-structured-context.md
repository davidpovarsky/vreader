# Feature 177 WI-4 — Structured AI Context Migration

Status: Gate 2 approved; implementation may begin  
Feature: #177 / GH #2138  
Branch: `chatgpt/original-ui-ios26`  
Baseline: `a257914406d6595451c7a49d702e2315691a50f2`

## Problem and invariant

Reader AI still derives Chat, Summarize, and Whole-book context from
`ReaderAICoordinator.loadedTextContent`. That flattened string loses PDF page,
EPUB resource, legacy section, and rendered-Markdown coordinate identity.

After WI-4, `AIDocumentSnapshot` and ordered `AIDocumentChunk` values are the
only reader-AI location authority. `loadedTextContent` remains only for TTS and
old-compatible selection paths. It may not reconstruct PDF/EPUB/AZW3 location,
chapter identity, or read-so-far boundaries.

## Prior art and rejected alternatives

- Swift task cancellation is cooperative, so every async snapshot application
  is guarded by cancellation plus a monotonically increasing generation.
- Readium distinguishes the resource `href`, intra-resource `progression`, and
  publication-wide `totalProgression`. WI-4 uses exact normalized `href` for
  resource identity and never converts either progression into a text offset.
- Rejected: fingerprint-only provider lookup. It cross-wires two mounted readers
  of the same book.
- Rejected: polling the registry. Attach/detach emits one exact-session event.
- Rejected: reconstructing PDF pages or EPUB resources from a flattened string.
- Rejected: subscribing TXT/MD providers to the existing unscoped position
  notification. Their host-owned registration receives the live view model's
  locator directly, preserving same-book session isolation.

## Scope and compatibility

In scope: structured Section/Chapter/Book-so-far resolution, structured
Whole-book reduction, exact-session coordinator wiring, live TXT/rendered-MD
registration, pre-resolved Summarize input, focused CI coverage, architecture
documentation.

Out of scope: WI-5 tools/authorization, search, OCR, MCP, provenance UI/payload
v2, FoundationModels, feature #178, UI changes, and unrelated reader refactors.

The existing extractor-based `AIAssistantViewModel.summarize` API remains for
compatibility and selection-driven Explain/Translate/Vocabulary/Ask behavior.
The production summary surface adds a resolved-context closure/input.

## Design

### Exact live provider lifecycle

1. Thread `ReaderContainerView.readerToken` into `ReaderAICoordinator`,
   `TXTReaderHost`, and `MDReaderHost`.
2. Add a small `AITextDocumentRegistration` lifecycle owner beside the WI-3
   providers. It attaches `AITXTDocumentProvider` or
   `AIMarkdownDocumentProvider` under the exact `AIDocumentSessionID`, updates
   the locator from the owning view model, and detaches with the registry's
   generation-bearing token.
3. The registration is an async generation-bearing state machine. It never
   attaches an interim chapter-only TXT provider: it awaits the already-open
   loader, then verifies mount/content generation before its single attach.
   Teardown/reopen invalidates and cancels the pending decode. A stale detach
   cannot remove a replacement registration.
4. TXT registers the canonical decoded display/search coordinate text. In
   continuous/full mode this is `textContent`; in chapter-paged mode it obtains
   the already-open loader's `fullDecodedText()` once, without reopening the
   file. It also supplies exact chapter bounds from
   `TXTReaderViewModel.chapterIndex`. MD registers
   `MDReaderViewModel.renderedText` plus its rendered-coordinate
   `MDReaderViewModel.headings`; raw-Markdown TOC offsets are forbidden for AI
   chapter resolution. Text providers populate `snapshot.currentChapterBounds`
   from those exact canonical coordinates.
5. `AIDocumentProviderRegistry` posts a minimal attach/detach change event only
   after an actual registry mutation. The event carries the exact session and
   attach/detach kind. A stale detach that does not mutate the registry emits
   nothing. `ReaderAICoordinator` listens only for its own session, invalidates
   its generation, and refreshes. A failed lookup is not cached.
6. Each format host also invokes an exact-session relocation callback on its
   owning coordinator/registration. The unscoped global
   `.readerPositionDidChange` notification remains for legacy/TTS behavior but
   is not an AI invalidation or stale-result authority. Provider snapshot
   identity validates the live AI position.
7. Existing PDF, Readium, and Foliate registrations remain the production
   source; no file reopen is introduced.

### Structured resolver

Add `AIDocumentContextResolver` in `Features/AIAgent/Document` with a pure,
Sendable request/result boundary:

- request: snapshot, ordered chunks, requested bounded scope, provider-supplied
  exact TXT/rendered-MD chapter bounds, and UTF-16 budget;
- result: text, source chunks/IDs, current locator, exactness, and structured
  coverage (included/dropped source IDs and reduction-stream ranges).

Rules:

- Section uses only `snapshot.currentSectionChunks`; oversized text is clamped
  around the exact local/global boundary inside that unit.
- Chapter uses provider snapshot `currentChapterBounds` only for TXT/rendered
  MD. The host registration derives those bounds from `TXTReaderViewModel`
  chapter metadata or `MDReaderViewModel.headings`; parent `tocEntries` are not
  accepted for MD. EPUB uses
  its exact current href resource. PDF and legacy degrade to Section.
- Book-so-far evaluates ordered chunks with `AIReadingBoundaryPolicy` in
  never-read-ahead mode. Unknown order is denied. TXT/MD slice the current
  segment at the exact UTF-16 boundary; PDF includes only pages at/before the
  current page; EPUB includes prior resources but omits the current resource
  when no exact intra-resource text offset exists; legacy remains its current
  bounded section. The final budget is applied after filtering from the newest
  allowed text backward.
- Remove progression-based ordering fallbacks from
  `AIReadingBoundaryPolicy`; progression remains display/navigation metadata.

### Coordinator and race safety

Split structured work out of the already-large `ReaderAICoordinator.swift`.
The coordinator owns one refresh task and generation. Every refresh resolves
the exact session anew, awaits snapshot/chunks, checks cancellation, generation,
session, and current snapshot identity, then publishes cached bounded results.
Relocation, scope change, TOC arrival, provider attach/replacement, and teardown
invalidate the prior generation. Missing providers yield a safe fallback title
or no context, never another session's provider or flattened PDF/EPUB text.

`scopedChatContext(_:)` exposes only a cache whose key matches exact session,
scope, provider generation, and snapshot generation. A scope/relocation change
immediately clears or invalidates mismatched context. `AIChatViewModel` gains an
async `onContextRefreshRequested` pre-send hook for every bounded scope. The
send pipeline awaits it before snapshotting citations or building context and
re-checks its operation token afterward. Thus an immediate send after a scope
change/relocation cannot use the prior cache. Whole-book keeps its existing
awaited pre-read, followed by the same assembly refresh. The single assembly
funnel preserves annotation blocks, counts, citations, `ChatContextAssembler`,
provider selection, sessions, and whole-book digest behavior.

### Summarize

`AIAssistantViewModel` receives a `summarizeResolved(...)` path whose context is
already structured and budgeted; it reuses the existing request lifecycle,
operation token, provider selection, error mapping, and bilingual follow-up.
One async resolved-summary launcher requests the currently selected scope from
the coordinator and submits that resolved text. Both `AISummaryTabView` and
`AIReaderPanel+DebugBridgeAIAction` call this launcher, so UI and end-to-end
verification cannot diverge. The visual hierarchy and scope chips do not
change. The old fullText/chapterBounds initializer/API remains available to
tests and non-production compatibility callers.

### Structured Whole-book

Add a provider-produced `AIWholeBookSourceManifest` (name may vary) containing
every ordered source-unit ID/index and an availability state plus text when
accessible. It also carries enumeration completeness (`complete` or
`bounded/unknown remainder`). PDF lists every page, Readium lists every
reading-order resource including inaccessible ones, TXT/MD list canonical
segments, and legacy lists its honestly bounded current unit with
`bounded/unknown remainder`. This is a structured provider API; missing units
can no longer disappear before coverage is computed, and a non-empty legacy
section can never masquerade as a complete one-unit book.

`WholeBookReducer` accepts the ordered manifest/reduction units, not a flattened
book string. The reducer preserves source
order, per-unit identity, max-call overflow, cancellation, hierarchical reduce,
and the existing phase machine. Existing `WholeBookCoverage` UTF-16 spans are
explicitly documented as virtual reduction-stream coverage, never navigation
coordinates; structured covered/dropped source-unit IDs retain the mapping.
Empty/inaccessible units are dropped explicitly and force `.partial`. An
incomplete enumeration also always forces `.partial` and records an honest
unknown-remainder marker in structured coverage.

`WholeBookRetrievalViewModel` accepts the structured input while retaining the
same armed/reading/ready/partial UI contract. `ReaderAICoordinator` fetches the
exact provider's whole-book manifest/reduction input for each requested read
and never uses `chunks()` as the Whole-book source or falls back to
`loadedTextContent` when structured retrieval fails.

## Test-first sequence

### RED — existing Feature177Mapping lane

Add resolver/policy/reducer pure tests for:

1. PDF page-50 Section and EPUB href-B Section.
2. EPUB Chapter ignoring `totalProgression`.
3. TXT emoji/surrogate exact Book-so-far boundary.
4. rendered-MD coordinate behavior.
5. PDF/EPUB no-read-ahead and unknown-order fail-closed.
6. ordered Whole-book units, overflow coverage, cancellation coverage, and
   inaccessible-unit partial coverage.

Update `Feature177Mapping.project.yml` only with the new production/test sources;
do not change `Feature177Core.project.yml`.

### RED — existing regression lane

Extend only `run_feature_177_regression_tests` with:

- `ReaderAICoordinatorChatContextTests`
- `AIAssistantViewModelScopeTests`
- `WholeBookReducerTests`
- `WholeBookRetrievalViewModelTests`
- a focused structured coordinator/registration integration suite

Pin wrong-flattened-content independence, late attach, exact same-book session
isolation, simultaneous same-book relocation storms, teardown during TXT full
decode, stale detach after replacement, stale snapshot suppression, immediate
send after scope/relocation, annotation/source-count assembly, rendered-MD
chapter offsets differing from raw Markdown offsets, structured summary scopes
through both UI and DebugBridge launchers, unchanged explicit selection
Translate, and safe missing-provider behavior.

### GREEN / REFACTOR

Implement the smallest production seams above, keep files near 300 lines by
using focused extensions/services, then run the mapping and regression lanes.
Retain every pre-WI-4 compatibility test.

## Verification and gates

1. Gate 2: independent read-only plan audit; resolve all High/Medium findings.
2. Demonstrate RED in the existing CI lanes (Windows cannot compile iOS).
3. Implement and get Feature177Mapping + targeted WI-4 regression green.
4. Gate 4: independent read-only implementation audit; resolve all High/Medium.
5. Re-run `Feature177Core` unchanged, mapping, and WI-4 regression workflows.
6. Run one normal full iOS 27 app compile through the existing workflow.
7. Update `docs/architecture.md`, commit with owner attribution, push the exact
   branch, and verify local/remote SHA equality plus a clean tree.

## Risks and mitigations

- SwiftUI lifecycle remounts: registration owner uses generation-bearing detach.
- Same-book readers: no unique/fingerprint fallback; exact session only.
- Late async snapshot: cancellation plus generation and session checks.
- Text coordinate drift: TXT decoded display text and MD rendered text only.
- Read-ahead leak: spoiler filter precedes budget/reduction; unknown denies.
- Whole-book missing units: explicit dropped IDs and partial state.
- Oversized source unit: Unicode-safe UTF-16 clamp never crosses its unit.
- Empty content, nil locator, malformed/foreign fingerprint, inaccessible
  resource, rapid relocation, rapid scope changes, provider replacement, and
  teardown each fail closed and are covered by focused tests.

## Gate 2 audit revision 1

Independent audit verdict: `REVISE` (2026-09-27).

Resolved in this revision:

1. MD Chapter authority is now explicitly the live view model's rendered-text
   headings; TXT uses its live chapter index. Raw MD TOC offsets are forbidden.
2. Whole-book now has a provider-produced ordered manifest that retains
   inaccessible unit identities and can report honest dropped source IDs.
3. Chat has an awaited, operation-token-guarded structured refresh before every
   bounded send; a stale synchronous cache cannot be sent.
4. AI relocation invalidation is exact-session host wiring, not the unscoped
   global notification.
5. TXT registration now has a single-attach async generation/teardown contract.
6. UI and DebugBridge Summarize share the same resolved-context launcher.

## Gate 2 audit revision 2

Independent round-2 verdict: `REVISE` (2026-09-27).

Resolved in this revision:

1. The manifest now carries enumeration completeness. A bounded legacy
   current-section manifest always produces partial coverage with an explicit
   unknown-remainder marker; it cannot claim Whole-book ready.
2. Production `runWholeBookRead()` is explicitly manifest-only. Ordered chunks
   remain a bounded-scope resolver input and cannot silently drop inaccessible
   Readium resources from Whole-book coverage.

Round-3 independent re-audit found no remaining High/Medium findings and
returned `APPROVE`.
