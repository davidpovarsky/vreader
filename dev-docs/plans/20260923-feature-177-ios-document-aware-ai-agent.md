# Feature #177 — iOS 27 document-aware AI agent platform

**Platform:** iOS/iPadOS 27.0, Xcode 27, Swift 6.
**GitHub:** #2138.
**Companion UI feature:** #178; missing designs tracked by needs-design #2137.
**Source brief:** `C:\Users\DAVID\Downloads\VREADER_AI_AGENT_IMPLEMENTATION_PROMPT.md`.

---

## 0. Verified baseline

The following claims were checked against the current branch before planning:

| Claim | Evidence |
|---|---|
| Branch is exactly 28 commits ahead of `lllyys/main`, 0 behind | `git rev-list --left-right --count lllyys/main...HEAD` returned `0 28`; HEAD `d6883a6f06bfe077209ff594172f433c52321553` |
| Working tree was clean before planning | `git status --short` returned no entries |
| Xcode 27 is the current stable toolchain | Apple released Xcode 27 on 2026-09-14; GitHub's dedicated `xcode-27` image exposes Xcode 27.0 build `27A266a` and iOS 27.0 SDK |
| Current project is not yet on that baseline | `project.yml` says iOS 17 / Xcode 16 and Readium 3.9.0; CI selects Xcode 26 and asserts SDK 26.* |
| Existing agentic stack must be extended, not replaced | `AITool`, `AIToolRegistry`, `AgenticChatDriver`, provider tool-use adapters, `AgenticToolRegistryBuilder`, and four read-only tools already exist under `vreader/Services/AI/` |
| Existing lexical index remains authoritative for keyword search | `PersistentSearchIndex` and the FTS5 stack are shared by reader search and agent tools |
| Current context mapping is structurally wrong for fixed-layout/live publications | `ReaderAICoordinator` owns one flattened `loadedTextContent`; PDF pages and EPUB spine resources are joined before scope resolution |
| Live renderer seams exist | Readium `Publication` is held by the main-actor reader VM/host; PDFKit owns an already-unlocked live `PDFDocument` inside `PDFViewBridge` |
| Mutation seams already post a completion bus | `PersistenceActor` annotation/highlight/bookmark mutation chokepoints post `.readerAnnotationsDidChange` after successful saves |
| Tool activity and spoiler-aware sources are designed | `tool-activity-artboards.jsx`, `design-notes/tool-activity-91.md`, `chat-context-artboards.jsx`, and `design-notes/chat-ai-scope-sources.md` |

The default `apple-devtools` runner currently exposes Xcode 26.6 only. A dispatch to its
custom `xcode-27` label failed before job creation, so it is not accepted as toolchain evidence.
The project CI migration below uses GitHub's documented dedicated `xcode-27` image directly.

## 1. Problem

VReader can chat with configured OpenAI-compatible and Anthropic providers and can run a small
read-only tool loop, but its book context is flattened into one string. That loses the exact PDF
page and EPUB resource identity needed for current-page context, spoiler-safe book-so-far reads,
navigable provenance, OCR, and agent tools. The app also lacks local semantic retrieval, MCP,
fine-grained tool authorization, observable tool traces, and a first-class Apple Foundation Models
backend.

## 2. Scope

### Included in feature #177

- Migrate deployment/build CI to iOS/iPadOS 27 and Xcode 27.
- Pin Readium 3.11.0, MCP 0.12.1, MLXSwiftLM 3.31.4, SwiftHuggingFace 0.11.0,
  SwiftTransformers 1.3.4 only if required by the resolved tokenizer path, and USearch 2.26.2.
- Add the isolated `vreader/Features/AIAgent/` layer and mirrored tests.
- Introduce structured chunks, source provenance, document snapshots, reading boundaries, and
  format-provider registration.
- Map TXT/MD by UTF-16 offsets, PDF by exact page, EPUB by Readium href/locator, and keep a bounded
  legacy AZW3/MOBI adapter.
- Preserve the existing static AI scopes while replacing their backing context assembly.
- Add spoiler-safe lexical/semantic/annotation retrieval, reader/navigation tools, and mutation
  tools with centralized authorization and confirmation semantics.
- Add explicit-download multilingual E5 embeddings, deterministic chunking, versioned USearch
  indexes, background indexing, and hybrid retrieval without replacing FTS5.
- Add Vision OCR fallback/cache for image-only PDF pages.
- Add MCP HTTP/OAuth profiles, discovery, dynamic tool adapters, result limits, SSRF controls, and
  Keychain-backed secrets.
- Emit tool lifecycle events and provenance; retain citations after agentic turns; migrate chat
  payloads forward without breaking v1 sessions.
- Add the already-designed chat activity/source UI and localize that implemented UI in English and
  Hebrew, including RTL/accessibility tests.
- Add Apple Foundation Models as a runtime-gated first-class backend with native tool adapters,
  dynamic profiles, structured output, and explicit on-device/PCC consent separation.

### Excluded from feature #177

- Replacing FTS5, the current OpenAI-compatible/Anthropic providers, PDFKit, SwiftData, or the
  annotation persistence model.
- Auto-downloading an embedding model, uploading book text without consent, or executing an MCP
  mutation without policy enforcement.
- Arbitrary UI for advanced settings. Those missing surfaces are feature #178 and needs-design
  #2137. Backend APIs and tests land here so that feature #178 can remain a thin UI composition.

## 3. Design coverage

### Depicted and allowed in #177

- Tool execution live/collapsed/expanded/error states: `tool-activity-artboards.jsx`.
- Source chips, navigable citations, whole-book retrieval progress, and ahead/spoiler marking:
  `chat-context-artboards.jsx`.
- Existing AI/data-sharing toggle vocabulary: `vreader-ai-toggles.jsx`.
- Existing provider/readiness/sheet shells remain unchanged and are reused.

### Missing and split to #178

Semantic model management, MCP profile management/auth state, detailed permission policy and
inline mutation confirmations, OCR status, Apple model runtime states, and their Hebrew RTL/iPad
variants are not depicted. Issue #2137 was filed immediately with `enhancement` + `needs-design`.
No placeholder or HIG-default substitute will be added under #177.

## 4. Architecture and invariants

1. **Structured source is authoritative.** Every model-visible excerpt is an `AIDocumentChunk`
   carrying a stable source unit, exact `Locator`, UTF-16 range where applicable, and provenance.
   A flattened string may be derived for provider payloads but never used to reconstruct location.
2. **Live-document registration is narrow.** Readium and PDF hosts register/unregister facade
   objects, not non-Sendable framework objects crossing actors. Registration lifetime matches the
   mounted reader and cannot outlive teardown.
3. **Spoiler policy is enforced below tools.** Every current-book read/retrieval path applies one
   `AIReadingBoundaryPolicy`; UI labels and model prompts are not security boundaries.
4. **Authorization is centralized.** Tool category + scope + server identity resolve through one
   allow/ask/deny decision. Deletes always ask. Confirmation continuations are single-resume,
   cancellation-aware, and time-bounded.
5. **Existing lexical search remains intact.** Semantic retrieval is additive and hybrid ranking
   receives lexical hits through an adapter. No FTS schema or role replacement.
6. **Local model acquisition is explicit.** No embedding weights download until a user action;
   indexes are derived, versioned, rebuildable, and removable.
7. **External data is untrusted.** Book text, OCR, annotations, and MCP results are data, never
   instructions. Prompt framing, output budgets, URL validation, and redaction apply at boundaries.
8. **Provider parity.** One execution coordinator maps the same tool catalog/events/provenance to
   the existing provider loop or Apple `LanguageModelSession` native tools.
9. **Persistence is version-gated.** Chat payload v2 decodes v1 losslessly; unknown future versions
   remain protected by the existing never-clobber behavior.
10. **Cancellation is end-to-end.** Extraction, indexing, OCR, MCP requests, confirmation waits,
    tool loops, and whole-book reduction check cancellation and release resources.

## 5. Dependency and toolchain decisions

| Package/framework | Pin | Product/use |
|---|---:|---|
| Readium Swift Toolkit | 3.11.0 | Existing Shared/Streamer/Navigator products |
| modelcontextprotocol/swift-sdk | 0.12.1 | `MCP` HTTP client/tool protocol |
| mlx-swift-lm | 3.31.4 | `MLXEmbedders`; `MLXHuggingFace` only if needed |
| swift-huggingface | 0.11.0 | model/tokenizer acquisition path |
| swift-transformers | 1.3.4 | only if the resolved E5 tokenizer requires it |
| USearch | 2.26.2 | local ANN index |
| FoundationModels | iOS 27 SDK | first-class Apple backend |
| Vision/PDFKit | iOS 27 SDK | OCR and exact PDF pages |

The embedding model is `intfloat/multilingual-e5-small`, dimension 384, max input 512 tokens;
queries use `query: ` and documents use `passage: ` for every language. Model/license metadata is
stored with the installation record and index version.

## 6. Work items and test-first order

| WI | Deliverable | RED test before implementation | Gate |
|---:|---|---|---|
| 1 | iOS 27/Xcode 27 + package pins + XcodeGen | dependency/version assertions fail on current files | Xcode 27 compile before feature code |
| 2 | Core models, provider registry, boundary policy | Codable/stable-ID/range/boundary tests | portable typecheck + focused XCTest |
| 3 | TXT/MD, PDF, Readium EPUB and legacy adapters | page-50, href, UTF-16, teardown/cancellation fixtures | document mapping suite |
| 4 | Coordinator/static-scope migration + whole-book reducer | current-section/book-so-far/partial-coverage regressions | existing AI scope suite |
| 5 | Authorization, confirmation broker, built-in read/navigation/mutation tools | allow/ask/deny, delete-always-asks, idempotency and notification tests | tool/annotation suites |
| 6 | Semantic model manager, chunker, metadata store, USearch and hybrid ranking | no-auto-download, E5 prefix/dimension, Hebrew ranking, stale-index rebuild | semantic suite + local integration |
| 7 | OCR cache/service + PDF fallback | native-text-first, image page OCR, exact provenance, memory/cancel tests | Vision-capable Xcode 27 tests; device leg for APIs unavailable in Simulator |
| 8 | MCP profiles/transports/OAuth/discovery/adapters/sanitizer | malformed/oversized/SSE/cancel/SSRF/secret tests | local MCP stub integration |
| 9 | Observable events, provenance and chat payload v2 | ordering, unknown/failed tool, citation retention, v1 decode | agent/session suites |
| 10 | Apple Foundation Models adapter + designed chat activity/source UI + EN/HE localization | availability/consent/tool-event parity, RTL/a11y snapshots | Xcode 27 build + simulator/device verification |

Each WI follows RED → confirm intended failure → implementation → focused green → subsystem green.
No WI starts by editing production code.

## 7. Expected write set

### New isolated layer

`vreader/Features/AIAgent/{Core,Document,Retrieval,Semantic,OCR,MCP,Permissions,Tools,UI,Settings}`
with mirrored `vreaderTests/Features/AIAgent/` suites. New files remain near 300 lines and split by
single responsibility.

### Narrow upstream integration hooks

- `project.yml` and `.github/workflows/build-unsigned-ipa.yml` — platform/dependencies/toolchain.
- generated Xcode project/package lock — XcodeGen/package resolution outputs only.
- `ReaderAICoordinator.swift` — consume structured snapshots instead of reconstructing offsets.
- Readium host/open/teardown files — register a publication facade.
- PDF bridge/container — register the already-unlocked `PDFDocument` facade.
- `AgenticToolRegistryBuilder.swift` — add the new catalog through adapters.
- `AIChatViewModel+Streaming.swift` — event sink/provenance retention and backend dispatch.
- `ChatMessage.swift` / `ChatSessionPayload.swift` — additive trace/provenance payload v2.
- `AIChatView.swift` / message-row extensions — committed activity/source designs only.
- `AISettingsSection.swift` — only existing designed toggles/entry wiring; #178 owns missing UI.
- string catalogs/resources — English/Hebrew strings for surfaces actually implemented in #177.
- `docs/architecture.md` and `README.md` — architecture, requirements, and user-visible capability.

Every touched pre-existing implementation file is recorded in the final Upstream Touch Ledger with
reason and approximate LOC delta.

## 8. Edge cases

- Empty/encrypted/corrupt books; missing local files; duplicate hrefs; href normalization; nil
  Readium locations; PDF page bounds; page rotation; image-only and mixed-text PDFs.
- Surrogate pairs, combining marks, CRLF, Hebrew/CJK/Latin text, empty chapters/pages, and chunks
  that cross paragraph/token limits without splitting a UTF-16 scalar boundary.
- Boundary at document start/end, unknown current location, spine/page transitions, read-ahead
  disabled, explicit whole-book opt-in, and sources returned from after the boundary.
- Model absent/downloading/cancelled/corrupt/out-of-disk; index version mismatch; interrupted atomic
  promote; deleted book/model; concurrent readers/index jobs.
- MCP redirects, private/link-local/loopback destinations, DNS rebinding, cancellation, OAuth state
  mismatch, server disconnect, unknown tools, malformed JSON, huge binary/text results, and secrets
  in logs.
- Confirmation cancellation/timeout/double callback/view teardown; duplicate mutation retries;
  deleted target between proposal and confirmation.
- Apple model unavailable/restricted/not-ready; unsupported language; on-device versus PCC path;
  provider switch during a turn; tool parity and event order across backends.
- v1 chat payloads, future payloads, partial traces, failed tools, and sources whose books are now
  remote-only or deleted.

## 9. Test plan

- Pure unit suites for models, chunking, stable IDs, boundaries, authorization, ranking, result
  sanitization, trace ordering, payload migration, and Hebrew localization keys.
- Provider fixtures for TXT/MD, exact PDF pages, Readium href/locator mapping, and live registry
  teardown. Tests must prove PDF page 50 never maps to page 1 and EPUB never infers href from a
  flattened global progression.
- Existing AI, provider, FTS5, annotation, navigation, and chat-session suites remain green.
- Integration stubs for OpenAI tool turns, Anthropic tool use, MCP HTTP/SSE/OAuth, model download,
  USearch persistence/reopen, OCR caching, and Apple tool-event mapping.
- `scripts/run-tests.sh` is the required repository test entry. Xcode 27 CI compiles/tests the
  Apple-only integrations; `apple-typecheck --local` is used only for portable Swift.
- Gate-5 production path: Library → open real EPUB/PDF/TXT/MD → AI → designed context/tool activity
  → source tap navigation. Device verification covers Vision/FoundationModels capabilities not
  available in Simulator. Hebrew is verified in RTL on compact iPhone and iPad.

## 10. Acceptance criteria

- PDF and EPUB context mapping is exact and spoiler-safe; TXT/MD UTF-16 behavior is unchanged.
- Existing lexical tools, normal chat, Anthropic/OpenAI tool chat, FTS5, annotations, navigation,
  and v1 chat sessions regress neither behavior nor persisted data.
- Built-in read/search/navigation and annotation mutation tools work with centralized permissions;
  deletes always require confirmation.
- Semantic search is user-installed, Hebrew-capable, versioned, rebuildable, and additive to FTS5.
- OCR prefers native PDF text, caches local Vision output, and returns exact page provenance.
- MCP secrets live in Keychain; HTTP/OAuth/discovery/adapters are bounded, cancellation-safe, and
  SSRF-hardened.
- Tool progress/failure/source provenance appears in the committed chat designs; source taps navigate
  correctly; agentic answers no longer discard citations.
- Apple Foundation Models builds on Xcode 27, is runtime-gated, uses native tools, and distinguishes
  on-device processing from network/PCC consent.
- Implemented #177 UI has complete English/Hebrew String Catalog coverage, localized accessibility,
  and verified RTL. Missing #178 UI remains absent rather than self-designed.
- Deployment target is 27.0; CI runs on `xcode-27`, asserts SDK 27.*, and the release build passes.
- Architecture/README, dependency table, Upstream Touch Ledger, new-file inventory, test evidence,
  known limitations, and final git status are delivered.

## 11. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Readium 3.11 migration breaks host APIs | Upgrade and compile alone in WI-1; fix only concrete compiler errors |
| Non-Sendable framework objects escape actors | facade protocols + main-actor registries; value DTOs cross boundaries |
| Whole-book work causes memory spikes | lazy streams, bounded chunks, persisted coverage, cancellation and atomic caches |
| Semantic dependency/API drift | exact package pins and an isolated adapter; no app-wide ML types |
| MCP SDK transport edge cases | adapter boundary and local protocol stub; explicit SSE/cancellation tests |
| Prompt injection from books/tools | untrusted-data framing, no secret exposure, schemas, budgets, sanitizer |
| UI scope outruns committed design | #178/#2137 split; implement only already-depicted #177 surfaces |

## 12. Gate status

- Gate 1 plan: complete in this document.
- Gate 2 independent agent dispatch: attempted with three read-only subagents; all returned
  `workspace is out of credits` before analysis. Rule 47's genuine-unavailability fallback is
  recorded in `.claude/codex-audits/plan-feature-177-gate2-audit.md`.
- Gate 3 begins only after that audit reaches `proceed` and the tracker row is `IN PROGRESS`.

