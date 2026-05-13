---
branch: triage/bug-185-provider-base-url-no-guidance
bug: 185
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Bug #185 row + detail entry to `docs/bugs.md`.
No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:
- `AIProviderEditSheet+Sections.swift:68`: Base URL TextField placeholder is
  `"https://api.example.com/v1"` only — no footer text, no per-kind dynamic hint.
- `AIProvider.swift:119` (OpenAI-compatible): `baseURL.appendingPathComponent("chat/completions")`
  — the app appends `/chat/completions` to whatever `baseURL` the user enters.
- `AnthropicProvider.swift:134` (Anthropic): `baseURL.appendingPathComponent("v1/messages")`
  — the app appends `/v1/messages`.
- `ProviderKind.swift` default base URLs: `.openAICompatible` → `"https://api.openai.com/v1"`;
  `.anthropicNative` → `"https://api.anthropic.com"`.
- If a user enters `https://openrouter.ai/api/v1/chat/completions`, the constructed URL
  becomes `https://openrouter.ai/api/v1/chat/completions/chat/completions` — produces a 404
  or unexpected provider error with no UI explanation of the cause.
- Correct entry for OpenRouter: `https://openrouter.ai/api/v1`
- No existing bug or feature tracks this gap (confirmed via grep across bugs.md + features.md).

## Verdict

ship-as-is — documentation only, no code risk.
