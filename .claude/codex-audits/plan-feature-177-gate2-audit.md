---
gate: 2
kind: plan-audit
feature: 177
plan: dev-docs/plans/20260923-feature-177-ios-document-aware-ai-agent.md
rounds: 1
final_verdict: proceed-with-recorded-design-split
---

# Gate-2 plan audit — feature #177

## Independence fallback

Three read-only subagents were dispatched for architecture, design coverage, and dependency risk.
Each failed before reading the tree with the same external condition: `workspace is out of credits`.
No independent finding was produced. This is the rule-47 manual fallback, not a claim that the
author's review is independent.

## Manual evidence sweep

| Area | Files/symbols checked | Finding and disposition |
|---|---|---|
| Context assembly | `ReaderAICoordinator.currentTextContent`, scoped-context methods, `loadBookTextContent` | Flat PDF/EPUB text cannot preserve exact page/href. Structured providers are required before tool expansion. |
| Agent loop | `AITool`, `AIToolRegistry`, `AgenticChatDriver`, `AIChatAgenticSupport` | Reuse the bounded loop; add event/context seams. Do not create a competing registry for cloud providers. |
| Citations | `AIChatViewModel+Streaming` agentic branch | Current tool reply clears citations. Plan correctly requires provenance accumulation and v2 persistence. |
| Search | `PersistentSearchIndex`, current search tools | FTS5 is shared production infrastructure. Semantic indexing must be additive. |
| Readium | `ReadiumEPUBReaderViewModel`, `ReadiumEPUBHost+Body.readyNavigator`, representable teardown | `Publication` is live/main-actor-owned. Register a facade with deterministic attach/detach; never leak it across actors. |
| PDF | `PDFReaderContainerView`, `PDFViewBridge`, debug live-document seam | Reuse the unlocked live `PDFDocument`; avoid reopening password-protected files. |
| Mutations | persistence annotation/highlight/bookmark APIs and `.readerAnnotationsDidChange` | Tools must call existing actor chokepoints so every successful mutation reaches current UI caches. |
| Sessions | `ChatMessage`, `ChatSessionPayload.payloadVersion == 1` | Additive v2 is viable; retain future-version never-clobber behavior and v1 decoding. |
| Toolchain | `project.yml`, package lock, unsigned-IPA workflow | Current iOS 17/Xcode 26 posture contradicts the brief; WI-1 compile-first ordering is mandatory. |
| Dependencies | official release manifests for Readium/MCP/MLX/USearch/Hugging Face | Requested pins are available and support iOS/Swift versions compatible with Xcode 27. Keep adapters isolated. |
| Design | tool activity, chat context, AI toggles, provider/readiness bundles | Chat traces/sources are depicted. Advanced MCP/model/OCR/permission/Apple-state UI is not; split to #178 and file #2137. |

## Findings

### High — original request combined designed and undesigned UI

Implementing every requested setting/status/control inside one feature would violate rule 51.

**Resolution:** feature #178 owns the missing UI and is blocked by needs-design #2137. Feature #177
continues backend and committed chat designs. No placeholder UI is permitted.

### High — Xcode 27 validation source was initially misclassified

The default remote Apple runner exposed only Xcode 26.6, but that does not mean Xcode 27 is absent.
Apple's stable release and GitHub's dedicated `xcode-27` image prove the requested baseline exists.

**Resolution:** use `runs-on: xcode-27`, assert Xcode 27 / SDK 27.*, and treat the failed custom
apple-devtools dispatch (no jobs created) as a harness limitation, not product evidence.

### Medium — feature size could hide unsafe sequencing

The brief spans toolchain, document mapping, retrieval, OCR, MCP, mutations, observability, UI, and
localization.

**Resolution:** ten ordered WIs with compile-first and document/boundary foundations before tools;
advanced undesigned UI split out. Each WI has a named RED test and subsystem gate.

### Medium — Apple and cloud backends could diverge

Two separate tool loops could produce different permissions/events/provenance.

**Resolution:** one catalog/execution policy/event model; adapters map that contract into existing
cloud provider turns or native Foundation Models `Tool` calls.

### Medium — live framework object lifetime

Readium `Publication` and PDFKit `PDFDocument` are not safe as unconstrained Sendable state.

**Resolution:** main-actor facade registries with explicit attach/detach tokens and value snapshots.
Teardown/cancellation tests are required before coordinator wiring.

### Medium — external dependencies and MCP are supply/network boundaries

Dependency drift, model downloads, and remote MCP results enlarge the attack/storage surface.

**Resolution:** exact pins, explicit model action, license metadata, Keychain secrets, URL/redirect
policy, bounded results, untrusted-data framing, and adapter-level integration tests.

## Verdict

`proceed-with-recorded-design-split`. Gate 1 is sufficiently concrete to start WI-1. Gate 2 does
not authorize feature #178 UI. Re-audit is required if a dependency pin changes, the facade design
crosses actor boundaries differently, or #2137 lands a design that widens the write set.

