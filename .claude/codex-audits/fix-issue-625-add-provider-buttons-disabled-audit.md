---
branch: fix/issue-625-add-provider-buttons-disabled
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Bug #184 / GH #625 — Add Provider buttons hidden in add-mode (audit log)

## Context

Bug #184 (reported by user 2026-05-14): in Settings → AI → Providers → Add
Provider, the "Save Key" and "Test Connection" buttons were always greyed-out
in add-mode. The tiny `caption2`/`tertiary` hint explaining the intentional
audit constraint (keychain-orphan prevention) was routinely missed; users
believed the feature was broken.

## Codex availability

Codex MCP unavailable this session (`stream disconnected before completion`
across all calls today). Manual fallback per rule 47.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Views/Settings/AIProviderEditSheet+Sections.swift` | hide Save Key / Test Connection in add-mode; promote hint notes | reviewed |

## Manual audit evidence

### Files read

- `vreader/Views/Settings/AIProviderEditSheet+Sections.swift` (full,
  post-edit). Confirmed the two `Section` blocks (`apiKeySection`,
  `testConnectionSection`) now branch on `existing != nil`:
  - **Edit-mode (`existing != nil`)**: shows the Save Key + Delete Key
    HStack and the Test Connection button + result text (unchanged
    behavior from pre-fix).
  - **Add-mode (`existing == nil`)**: shows only a promoted
    `.font(.footnote)` + `.foregroundStyle(.secondary)` note text. No
    button widgets. Pre-fix had disabled buttons + `.caption2`/`.tertiary`
    text; post-fix has only the promoted text.
- `vreader/Views/Settings/AIProviderEditSheet.swift` (full). Confirmed
  `existing: ProviderProfile?` is the canonical add-vs-edit flag used
  throughout the sheet (e.g. inEditMode, title selection). My branch
  uses the same flag — consistent with the rest of the file.
- The top-level Save action (`onSave`) in `AIProviderEditSheet` calls
  `addProfile` / `updateProfile` on `AISettingsViewModel`, which
  atomically persists profile + key. The audit-design rationale
  documented in the comments still holds — my fix only hides the
  redundant inline buttons.

### Symbols verified

- `if let _ = existing` is valid Swift; mirrors the `inEditMode`
  computed property pattern (`existing != nil`).
- `.font(.footnote)` + `.foregroundStyle(.secondary)` — standard
  SwiftUI text styling, one tier more prominent than the prior
  `.caption2` + `.tertiary`.
- `accessibilityIdentifier("editProviderSaveKeyNote")` +
  `accessibilityIdentifier("editProviderTestConnectionNote")` — new
  IDs for the promoted notes. Grep confirms no collision with
  existing IDs.

### Edge cases checked

1. **Add-mode → user enters API key → taps top-level Save**: existing
   flow unchanged. `AISettingsViewModel.addProfile` writes profile +
   key atomically. No keychain orphan risk.
2. **Add-mode → user taps Cancel without saving**: no keychain entry
   was written (Save Key button removed). Pre-fix also had no
   keychain write in this case (button was disabled). Same final
   state, cleaner UX.
3. **Edit-mode user with saved key**: Save Key + Delete Key buttons
   still visible, Test Connection still visible. Verified by reading
   the `if let _ = existing` branch.
4. **Edit-mode user with unsaved local edits**: Save Key button is
   enabled only when `apiKey.isEmpty` is false (existing logic).
   Disabled state preserved when input is empty.
5. **Test Connection in edit-mode without saved key** (e.g., user
   just deleted the key): button is disabled via
   `!isAPIKeySaved`. Existing logic.
6. **VoiceOver/accessibility**: replaced inline disabled buttons +
   tertiary hint with a single visible secondary-weight note. The
   accessibility tree contains fewer disabled elements (less noise
   for VoiceOver users) and the note reads as a clear next-step
   instruction.

### Risks accepted

- **Note text is hardcoded English** — same as bug #185's hint, same
  treatment. Localization is a separate app-level concern.
- **No unit test added** — pure SwiftUI conditional View rendering.
  Same rule 10-tdd.md exception as bug #177 (layout-only) and
  bug #185 (conditional view styling). Pre-FIXED simulator verify
  + visual screenshot covers the change.

### Concurrency / Swift 6

- `existing` is `ProviderProfile?` (Sendable value type). No actor
  concerns introduced by the branching.
- SwiftUI body remains MainActor-bound; no cross-actor work.

### VReader compliance

- Swift 6 strict concurrency: clean.
- `@MainActor` correctness: SwiftUI body inherits implicit MainActor.
- File size: AIProviderEditSheet+Sections.swift grew from 210 → 220
  lines. Well under 300.
- Bridge safety: not applicable (no WKWebView / JS surface).

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — matches bug body's prescribed fix exactly | n/a |

## Final verdict

**ship-as-is** — minimal SwiftUI conditional render that preserves the
existing audit-design intent (atomic profile + key save) while removing
the source of user confusion (disabled-button visibility). Pre-FIXED
simulator verify confirmed the new add-mode layout: only the SecureField
+ promoted footnote-weight note per section, no greyed-out buttons.
