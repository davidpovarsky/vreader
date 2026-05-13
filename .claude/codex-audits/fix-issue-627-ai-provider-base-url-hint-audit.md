---
branch: fix/issue-627-ai-provider-base-url-hint
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Bug #185 / GH #627 — AI provider Base URL hint (audit log)

## Context

Bug #185 (reported by user 2026-05-14): the AI provider editor's Base URL field
shows only a placeholder with no explanation of what path the app appends. Users
who enter a full endpoint URL (e.g. `https://openrouter.ai/api/v1/chat/completions`)
get a silent doubled path (`…/chat/completions/chat/completions`) → 404 or
opaque provider error.

## Codex availability

Codex MCP unavailable this session (`stream disconnected before completion`
across all calls today). Manual fallback per rule 47.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Services/AI/ProviderKind.swift` | added `endpointPathHint` computed property | reviewed |
| `vreader/Views/Settings/AIProviderEditSheet+Sections.swift` | wired hint as Section footer | reviewed |
| `vreaderTests/Services/AI/ProviderKindTests.swift` | 4 new tests for hint mapping | reviewed |

## Manual audit evidence

### Files read

- `vreader/Services/AI/ProviderKind.swift` (full, post-edit). Confirmed
  `endpointPathHint` follows the same `switch self` pattern as
  `defaultBaseURL`, `defaultModel`, `displayName` — peer property of the
  enum, no new dependencies.
- `vreader/Views/Settings/AIProviderEditSheet+Sections.swift` (target
  section). Confirmed conversion `Section("Endpoint") { … }` →
  `Section { … } header: { Text("Endpoint") } footer: { Text(kind.endpointPathHint) }`
  is mechanically equivalent SwiftUI syntax that adds the dynamic footer
  without changing header / content positioning. `kind` is the existing
  `@State var kind: ProviderKind` that already drives the picker reset
  on change — the footer subscribes naturally via SwiftUI's value
  observation.
- `vreader/Services/AI/AIProvider.swift` line 119: confirmed
  `chat/completions` is the appended path for OpenAI-compatible.
- `vreader/Services/AI/AnthropicProvider.swift` line 134: confirmed
  `v1/messages` is the appended path for Anthropic.
- `vreaderTests/Services/AI/ProviderKindTests.swift` (existing 10 tests).
  Confirmed test-suite style is `@Suite` + `@Test` (Swift Testing).
  My 4 additions match the style.

### Symbols verified

- `ProviderKind.endpointPathHint: String` — new computed, pure function.
- `Section { … } header: { … } footer: { … }` — SwiftUI 3-arg
  initializer; available since iOS 15.
- `kind.endpointPathHint` — accessed inside SwiftUI body; reactive to
  `@State kind` changes (verified visually on simulator).
- `.accessibilityIdentifier("editProviderBaseURLHint")` — new ID for
  the footer Text. No collision with existing IDs (grep confirms
  unique).

### Edge cases checked

1. **Picker switches OpenAI ↔ Anthropic**: footer dynamically updates
   (verified on iPhone 17 Pro Sim — captured both screenshots).
2. **Empty kind / no kind selected**: not reachable — `kind` is always
   one of the 2 cases per `ProviderKind.allCases` (verified by
   `caseIterableOrderStable` test).
3. **Dynamic Type / VoiceOver**: footer Text inherits Section footer
   styling; reads naturally as a continuation of the Base URL field
   (no additional accessibility config needed).
4. **Hint text contains backticks**: SwiftUI Text renders backticks as
   literal characters (not Markdown — Text() with String doesn't auto-
   parse Markdown). Confirmed visually on simulator: backticks display
   literally, which matches user expectation of "code style" in a hint.
5. **Hint goes out of date if AIProvider.swift / AnthropicProvider.swift
   change their append path**: pinned by the 2 unit tests
   (`endpointPathHintOpenAIMentionsAppendedPath`,
   `endpointPathHintAnthropicMentionsAppendedPath`). If the production
   append-path string changes, the test text-match would still pass
   (loose match on `/chat/completions` / `/v1/messages` substring),
   but a follow-up developer would need to update the hint. Acceptable
   — the test cost would catch a complete divergence (e.g. someone
   removes `/chat/completions` entirely).

### Risks accepted

- **Hint text is hardcoded in ProviderKind, not localized**: rest of
  the codebase has similar hardcoded English strings (e.g. `displayName`).
  Localization is a separate concern handled at the app level, not
  per-bug-fix scope.
- **Backticks-as-literal rendering**: not Markdown-rendered. Documented
  as expected behavior; user-facing wording reads cleanly as plain text
  in the simulator.

### Concurrency / Swift 6

- `ProviderKind` is `Codable`, `CaseIterable`, value-type enum: no actor
  concerns.
- Section footer is SwiftUI body code, implicit MainActor: clean.

### VReader compliance

- Swift 6 strict concurrency: clean.
- `@MainActor` correctness: SwiftUI View body is MainActor-bound; works
  with `@State var kind` directly.
- File size: ProviderKind.swift grew from 58 → 73 lines, AIProviderEditSheet
  +Sections.swift grew by ~8 lines. Both well under 300.
- Bridge safety: not applicable (no JS interpolation or WKWebView surface).

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — minimal, matches bug body's prescribed fix, tested, visually verified | n/a |

## Final verdict

**ship-as-is** — minimal, well-tested, visually verified on simulator. New
`ProviderKind.endpointPathHint` is a pure peer property of existing
`defaultBaseURL` / `defaultModel` / `displayName`. View wiring is one Section
syntax conversion. 4 new unit tests pin behavior. Pre-FIXED simulator verify
confirmed both Provider Type picks render the correct dynamic hint.
