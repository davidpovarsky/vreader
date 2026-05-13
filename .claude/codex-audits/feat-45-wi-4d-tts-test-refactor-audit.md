---
branch: feat/45-wi-4d-tts-test-refactor
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Feature #45 WI-4d — TTS test refactor helper method (audit log, PARTIAL)

## Context

WI-4d set out to refactor Feature40/41 XCUITest verification tests to use
`vreader-debug://tts?action=start` instead of `ttsButton.tap()`, leveraging
WI-4c-b's shipped URL handler. Investigation revealed a simctl-from-XCUITest
-sandbox URL delivery blocker (documented in the plan doc). WI-4d was
re-scoped to ship only the clean helper abstraction; the test refactors
are deferred to a future WI-4e pending the routing question.

## Codex availability

Codex MCP unavailable this session (`stream disconnected before completion`
across all calls today). Manual fallback per rule 47.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreaderUITests/Verification/Helpers/VerificationDebugBridgeHelper.swift` | added `ttsAction(_:)` + `DebugCommand.ttsURL(action:)` | reviewed |
| `dev-docs/plans/20260513-feature-45-verification-harness-sweep.md` | appended WI-4d plan + Gate 2 audit + PARTIAL outcome | reviewed |

## Manual audit evidence

### Files read

- `vreaderUITests/Verification/Helpers/VerificationDebugBridgeHelper.swift`
  (full, post-edit). Confirmed `ttsAction` follows the exact same pattern
  as `seedFixture` / `settleApp` / `snapshotApp`:
  fail-on-construction-failure + `send(url)`. Symmetric with peer methods.
- `DebugCommand` enum's new `ttsURL(action:)` mirrors `seedURL(fixture:)` /
  `settleURL(token:)` / `snapshotURL(dest:)` shape: URLComponents +
  vreader-debug scheme + matching host + single queryItem.
- `vreader/Services/DebugBridge/DebugCommand.swift` already parses
  `vreader-debug://tts?action=<action>` correctly (shipped in WI-4c-b,
  with 4 unit tests in DebugCommandTests).

### Symbols verified

- `URL(string:)` initializer pattern: matches existing `resetURL` shape.
- `XCTFail` import: indirectly via `XCTest` already imported at file head.
- `send(_:)` private method: existing, takes a `URL`, fire-and-forget via
  posix_spawn.

### Edge cases checked

1. **`action: ""`** (empty): `URLQueryItem(name: "action", value: "")` → URL
   constructed but production handler will reject "" as `invalidParam(action,
   reason: "expected start|stop, got ")`. Helper does its job; production
   surfaces the error.
2. **`action: "garbage"`** (invalid): URL constructed; production handler
   raises `invalidParam`. Same as above.
3. **`action: "start"` / `action: "stop"`** (valid): URL constructed
   correctly, parses to `.tts(action: "start"/"stop")` in production.
4. **`xcrun simctl` exec failure** (the discovered blocker): silent — fire-
   and-forget pattern. Documented in plan doc; not fixed in this WI.
5. **Calling `ttsAction` when no reader is mounted**: production observer
   in ReaderContainerView only attaches when the View is in the hierarchy.
   Notification fires but no observer → no-op. Defensive, no crash.

### Risks accepted

- **Helper compiles + ships, but no XCUITest exercises the new path yet** —
  acceptable because the helper is additive (zero behavioral risk in
  Release; XCUITest-only file) and unblocks future iterations once the
  simctl routing question is resolved.
- **Tests still XCTSkip on AVSpeech audio session** — pre-existing behavior,
  not introduced by this WI. Documented in plan doc as deferred to WI-4e.

### VReader compliance

- Swift 6 strict concurrency: clean (helper is an iOS test target,
  XCUITest classes are MainActor-bound naturally).
- File size: VerificationDebugBridgeHelper.swift grew from 200 → 220 lines.
  Well under 300.
- Bridge safety: not applicable (this is a TEST helper, not a JS/WKWebView
  bridge).

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | Method follows established peer-helper pattern exactly | n/a |
| 2 | n/a | Documented simctl-from-sandbox blocker thoroughly in plan doc with three concrete unblock paths | acknowledged in plan |

## Final verdict

**ship-as-is** — additive helper method that follows existing patterns 1:1.
Compiles, doesn't change any test behavior, leaves the test refactors clearly
documented as deferred to a future WI-4e pending the simctl-from-sandbox
investigation. Net: small forward progress on the harness's surface area,
zero regression risk.
