---
branch: triage/bug-184-add-provider-buttons-disabled-add-mode
bug: 184
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Bug #184 row + detail entry to `docs/bugs.md`.
No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:
- `AIProviderEditSheet+Sections.swift:145`: `Save Key` button:
  `.disabled(apiKey.isEmpty || existing == nil)` — always disabled when `existing == nil`
  (add-mode), regardless of whether the user has typed an API key.
- `AIProviderEditSheet+Sections.swift:185`: `Test Connection` button:
  `.disabled(testInFlight || !isAPIKeySaved || existing == nil)` — also always disabled
  in add-mode due to the `existing == nil` condition.
- `AIProviderEditSheet.swift:28-31` (key decisions comment): explicitly documents the design
  intent: "Add-mode 'Save Key' is disabled to prevent keychain orphans on Cancel
  (round-1 audit fix [4])." This was a deliberate audit decision.
- `AIProviderEditSheet+Sections.swift:156-160`: hint text is rendered as `caption2`/`tertiary`
  — tiny and very low contrast. Same for the "Test Connection" hint at lines 195-199.
- The bug is not the disable logic itself (correct) but the UX consequence: both buttons
  are visible and appear tappable, but do nothing in the primary user flow (adding a provider).
  Users believe the feature is broken rather than reading the caption hint.
- Not a duplicate of Bug #174 (edit-mode tap discoverability) — different mode, different
  surface, different root cause.

## Verdict

ship-as-is — documentation only, no code risk.
