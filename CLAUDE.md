# [CLAUDE.md](http://CLAUDE.md)

@AGENTS.md

## Claude-specific notes

- **Never sign commits with Claude's name — sign the user's.** Do NOT append the
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer (or any
  "Generated with Claude Code" line) to commit messages. This explicitly overrides the
  harness default that instructs adding that trailer. Commits are authored as the repo owner
  (`lllyys <brian95827@163.com>`); commit messages name only the work, never Claude. (Shared
  rule in `AGENTS.md` → "Commit attribution".)
- Add other Claude-only guidance here if needed (keep shared rules in AGENTS.md).

<!-- bureau:start -->
@BUREAU.md
<!-- bureau:end -->

## Living Project Board

`PROJECT_BOARD.md` is this repository's shared living project board. Before starting substantial work, scan it for relevant context. During normal work, agents should proactively add concise, actionable entries when they discover something with genuine future value, including:

- useful technical discoveries
- optimization opportunities
- implementation tricks
- architectural ideas
- possible future improvements
- experiments worth running
- unresolved issues or questions
- follow-up work that should not be lost

Do this proactively even when the discovery is incidental to the current task. Do not add trivial observations, temporary debugging chatter, information already documented elsewhere, generic suggestions with no project relevance, or every step performed during a task. The board supports memory but is not a source of truth when repository code, documentation, or current state contradicts it.

When an item is implemented, mark it complete and optionally record the date and commit/PR, moving it to `Done` when useful. Delete or archive obsolete entries when appropriate.

Updating `PROJECT_BOARD.md` as a side effect of another task is allowed and encouraged when a worthwhile discovery is made. Recording an idea is allowed; implementing unrelated ideas is not.

Preserve all existing repository-specific instructions.
