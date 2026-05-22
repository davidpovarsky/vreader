---
branch: fix/issue-1138-debugbridge-seed-sessions
threadId: 019e4d81-636f-7d70-a353-b0538b4dd544
rounds: 3
final_verdict: ship-as-is
date: 2026-05-22
---

# Codex Audit — fix/issue-1138-debugbridge-seed-sessions (Bug #263 / GH #1138)

**Verdict: ship-as-is** (3 rounds; thread `019e4d81-636f-7d70-a353-b0538b4dd544`)

## Scope

DEBUG-only `vreader-debug://seed-sessions?book=<fingerprintKey>[&seconds=<n>]`
command that seeds a deterministic 6-session spread of `ReadingSession` rows so
the reading dashboard (Feature #58) renders non-zero per-window totals CU-free.

Files audited:
- `vreader/Services/DebugBridge/DebugCommand.swift` (parser arm + enum case)
- `vreader/Services/DebugBridge/DebugBridge.swift` (protocol method + dispatch + stableErrorMessage)
- `vreader/Services/DebugBridge/RealDebugBridgeContext.swift` (error case + inventory header)
- `vreader/Services/DebugBridge/RealDebugBridgeContext+SeedSessions.swift` (handler)
- `vreader/Services/PersistenceActor+Stats.swift` (`seedSyntheticReadingSessions` seam)
- tests: `DebugCommandTests`, `DebugBridgeTests`, `RealDebugBridgeContextTests`, `PersistenceActorStatsReadTests`

## Findings + resolution

### Round 1 — verdict: follow-up-recommended
- **Medium** — production `now=Date()` not deterministic near midnight: a fixed
  `now − 1h` today-band anchor slips into yesterday in the first hour after local
  midnight (today window → 0); "Year" (YTD) is date-dependent.
  → **Fixed** (commit 57b76f11): today band re-anchored to the midpoint of the
  elapsed local day (`startOfDay(now) + elapsed/2`), always strictly inside
  `[startOfDay(now), now)`. Injectable `calendar` param added (default `.current`).
  "Year"/YTD date-dependence documented as a caveat (Year ≥ 180d, Year ≤ all
  always hold). Regression test `…todayBandSurvivesMidnightEdge` added.
- **Low** — stale "Idempotent" doc + out-of-sync handler-inventory header.
  → **Fixed** (57b76f11).
- **Low** — release gate doesn't scan the new seam name.
  → **Accepted out of scope** (seam is `#if DEBUG`-gated; existing gate already
  catches the DebugBridge surface; PATTERN expansion is separate harness tooling).
  Codex agreed.

### Round 2 — verdict: changes-required
- **Medium** — the today-band session's nominal interval can extend PAST `now`
  for runs within ~2× duration of midnight → future per-book `lastReadAt`
  (`lastReadAt = endedAt ?? startedAt`) skews the last-read column + sort.
  → **Fixed** (commit 895b508b): every seeded session's `endedAt` clamped to
  `min(startedAt + duration, now)`. `durationSeconds` keeps the requested value
  (per-window totals stay exact multiples; the aggregator sums `durationSeconds`,
  not the interval). Midnight test strengthened (runs at 00:10 with clamp
  engaged; asserts today total = 600s AND every `endedAt ≤ now` AND per-book
  `lastReadAt ≤ now`).
- **Low** — stale `// Bands: now-1h, …` test comment. → **Fixed** (895b508b).

### Round 3 — verdict: ship-as-is
No findings. Confirmed: (a) clamp fully closes the future-`lastReadAt` hole for
all run times; (b) per-window totals still exact; (c) strictly-increasing
rolling ladder intact; (d) no new issue.

## Audit areas confirmed clean (round 1)
- DEBUG-gating: every new symbol (`seedSessions` case, `seedReadingSessions`
  protocol method, `seedSyntheticReadingSessions` seam, `invalidFingerprintKey`)
  is `#if DEBUG`-gated → zero Release leak.
- Real-boundary insertion: the seam uses the same `ReadingSession` +
  `ModelContext.save()` path as production `SwiftDataSessionStore.saveSession`;
  no parallel persistence path. `recomputeStats` refresh is correct + idempotent.
- Edge cases: malformed key (throws + seeds nothing), orphan key (no Book row),
  empty/zero/negative `seconds`, duplicate params — all handled.
- Concurrency: PersistenceActor actor-isolation + @MainActor handler boundary —
  no Sendable/isolation hazard.
