---
branch: chore/agents-md-no-self-designed-ui-rule
date: 2026-05-15
final_verdict: ship-as-is
---

## Scope

Adds a new binding rule to AGENTS.md + a detailed rule file under `.claude/rules/`:

- `.claude/rules/51-no-self-designed-ui.md` — full rule (NEW): never invent UI/UX when no committed claude.ai/design surface exists; file a `needs-design` GH issue and stop the slice.
- `AGENTS.md` — single bullet added under the working-agreement list, between the "Feature implementation workflow" and "Parallel execution" pointers, summarizing the rule + pointing to file 51.

No Swift source changes. No test changes. Documentation-only.

## Audit

The rule is grounded in:

- **User directive 2026-05-15** after filing feature #60 (visual identity v2 design bundle at `dev-docs/designs/vreader-fidelity-v1/`).
- **Memory record** `feedback_no_self_designed_ui.md` already filed locally.
- **GH issue comment** `lllyys/vreader#718#issuecomment-4460792468` already records the rule against the active design context.

This commit escalates the rule from per-session (memory) + per-issue (GH comment) to **repo-binding via AGENTS.md**, which is the canonical pointer all agents read at session start (Claude reads it via `@AGENTS.md` in CLAUDE.md; Codex reads it directly).

Structure matches existing rule pointers (e.g., entries 47/48/49 are short summary + `.claude/rules/<N>-<slug>.md` pointer + key bullets). New entry placed between #47 (feature-workflow) and #48 (parallel-execution) so the visual flow reads: how to plan a feature → where its UI comes from → how to parallelize the work. Logical narrative ordering.

The detailed file at `.claude/rules/51-no-self-designed-ui.md` covers:
- Hard rule + scope (what counts as UI under the rule)
- "What designed means" test (must be in `dev-docs/designs/...`, by name, by visual depiction — no fuzzy "looks similar")
- Workflow (stop slice → file `needs-design` GH issue → pause row → parallel slices continue → user loop)
- Explicit not-in-scope list (system chrome, DebugBridge, hooks, scripts, refactors, etc.)
- 5-row anti-pattern table
- Origin (one-way design loop, not round-trip)

## Verdict

ship-as-is — documentation-only escalation of an already-recorded rule. No code risk.
