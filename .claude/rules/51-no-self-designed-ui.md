# 51 — UI/UX from claude.ai/design only

Binding rule for every agent (Claude, Codex, others). Applies to every feature, bug fix, refactor, and verification slice that introduces a new visible UI element.

## Hard rule

**Do not invent UI/UX.** If a feature, bug fix, or slice needs a UI element on a surface that is NOT depicted in a committed design bundle under `dev-docs/designs/...`, stop that slice and file a `needs-design` GitHub issue. The user manually carries it through `claude.ai/design`, re-handoffs a fresh bundle, and only then does the slice resume.

This applies to:

- New SwiftUI / UIKit views, sheets, modals, popovers, alerts, toasts.
- New rows, sections, settings entries, buttons, indicators, or empty states within existing screens.
- New visual states (loading, error, empty, partial, in-progress) when not depicted in the design.
- "Placeholder" UI introduced with intent to re-skin later — same prohibition.
- UI affordances introduced by a bug fix (e.g., a new confirmation dialog, a new status chip) — same prohibition.
- AZW3/Foliate-js / EPUB CSS / WKWebView injection — same prohibition when it changes visible chrome.

## What "designed" means

A surface is **designed** when ALL of the following hold:

1. A committed design bundle exists at `dev-docs/designs/<bundle-name>/`.
2. The specific surface (screen, sheet, popover, interaction state) is depicted in that bundle's HTML/JSX/screenshots — by name and by visual content.
3. "Looks similar to existing X" does NOT count. "Inherits the same chrome" does NOT count. The actual surface must appear in the design.

If you cannot point at a file in `dev-docs/designs/` that shows the surface you are about to build, it is **not designed**.

## Workflow

When you reach a slice that would touch undesigned UI:

1. **Stop that slice.** Do not write the View. Do not write a placeholder. Do not improvise.
2. **File a GitHub issue**:
   - Title: `Design needed: <surface name> for feature #<N>` (or `for bug #<N>`)
   - Labels: `enhancement` + `needs-design`
   - Body must include:
     - The surface being requested (screen / sheet / state)
     - The parent feature or bug (`Refs #<N>`)
     - The user-facing behavior the UI must expose
     - Screenshots of the current chrome if any
     - List of states the design must cover (default, loading, error, empty, etc.)
3. **Pause that slice** in the tracker — add a `BLOCKED: needs-design (#<new-issue>)` note on the WI or bug row.
4. **Continue parallel slices** that DO have design — see `.claude/rules/48-parallel-execution.md` for safe parallel execution.
5. **User loop**: the user manually takes the `needs-design` issue through `claude.ai/design`, gets a handoff bundle, and commits it under `dev-docs/designs/...` in a separate PR. The slice can then resume.

## What is NOT covered by this rule

- **System chrome (status bar, home indicator, dynamic island)** — iOS / SwiftUI handles these by default; no design needed.
- **Pure code changes with no visible delta** — refactors, persistence-only fixes, performance fixes, test-only changes.
- **Existing-surface bug fixes that restore broken UI back to its designed state** — fixing a typo in a label, fixing a hidden button, etc.
- **Verification-only artifacts** — XCUITest helpers, DebugBridge surfaces (`vreader-debug://...`), `dev-docs/verification/*` markdown — these are dev-only, never user-visible in Release.
- **CLI / config / hook / script files** — never user-facing.

## Anti-patterns

| Anti-pattern | Why it fails | Right move |
|---|---|---|
| "I'll match the existing chrome for now" | That's self-designed UI. Existing chrome IS the thing being replaced (feature #60). | File `needs-design`. |
| "Just a placeholder until v2" | Placeholders are committed code that ships in releases. Fragmenting UI for 2-3 versions is worse than pausing. | File `needs-design`. |
| "It's a small dialog, an Apple HIG default works fine" | HIG defaults look fine in isolation but clash with the specified design system over time. | File `needs-design`. |
| Inventing UI for a bug-fix toast / status chip / error sheet | Bug fixes don't escape this rule — they can introduce UI debt the same way features do. | File `needs-design`. |
| Inventing UI in a feature-workflow Gate 3 implementation because the WI list said "small change" | Gate-3 must reference the designed surface; if no design exists for a WI's UI, that WI itself was misclassified in Gate 1 — escalate. | Stop the WI, file `needs-design`, fix the Gate-1 plan. |

## Origin

2026-05-15 user directive after filing feature #60 (visual identity v2 design bundle). The user wants a one-way design loop:

```
design tool → handoff bundle → commit → implement
```

and explicitly rejects the round-trip:

```
agent invents UI → ships → user notices → user redesigns → re-implement
```

The cost of pausing a slice to file `needs-design` is far below the cost of producing UI debt that has to be re-skinned later. This rule encodes that trade-off.
