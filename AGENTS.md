# [AGENTS.md](http://AGENTS.md)

Shared instructions for all AI agents (Claude, Codex, etc.).

- You are an AI assistant working on the project.
- Use English unless another language is requested.
- Follow the working agreement:
  - Run `git status -sb` at session start.
  - Read relevant files before editing.
  - Keep diffs focused; avoid drive-by refactors.
  - Do not commit unless explicitly requested.
  - Keep code files under \~300 lines (split proactively).
  - Keep features local; avoid cross-feature imports unless truly shared.
  - **Research before building**: For new features, search for industry best practices,  
    established conventions, and proven solutions (web search, official docs, prior art in  
    popular open-source projects). Don't invent when a well-tested pattern exists.
  - **Edge cases are not optional**: Brainstorm as many edge cases as possible — empty input,  
    null/undefined, max values, concurrent access, Unicode/CJK, RTL text, rapid repeated  
    actions, network failures, permission denials. Write tests for every one.
  - **Test-first is mandatory** for new behavior:
    - Write a failing test (RED), implement minimally (GREEN), refactor (REFACTOR).
    - Coverage thresholds are enforced — `ut` fails if coverage drops.
    - Exceptions: CSS-only, docs, config. See `.claude/rules/10-tdd.md` for full scope.
  - Run ut for gates.
  - **Task workflow** (three files, one flow):
    - `docs/tasks.md` — **inbox**. User writes free-form descriptions. Agent triages (classify only, do not fix or implement during triage). See `docs/tasks.md` for classification rules, deduplication, and triage record format.
    - `docs/bugs.md` — **bug tracker**. Something implemented but broken. Follow the bug fix workflow defined in `docs/bugs.md` (Understand → RED → GREEN → REFACTOR → Verify → Track).
    - `docs/features.md` — **feature tracker**. Something never implemented. Must be planned before implementation (Problem, Scope, Edge Cases, Test Plan, Acceptance Criteria). See `docs/features.md` for plan template and statuses.
  - **Key rules**:
    - Bugs vs features: broken implementation → `docs/bugs.md`; never implemented → `docs/features.md`. Never mix.
    - Triage is classification only — do not fix bugs or implement features during triage.
    - Features must reach `PLANNED` status before `IN PROGRESS`. Exception: features resolved incidentally by a bug fix.
- AI coding tool auth:
  - **Prefer subscription auth over API keys** for all AI coding tools (Claude Code, Codex CLI, Gemini CLI). Subscription plans are dramatically cheaper for sustained coding sessions — API billing can cost 10–30x more.
  - Claude Code: log in with Claude Max subscription. Codex CLI: `codex login` with ChatGPT Plus/Pro. Gemini CLI: Google account login.
  - API keys work as a fallback for light or automated usage.

