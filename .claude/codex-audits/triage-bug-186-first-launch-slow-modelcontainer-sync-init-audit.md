---
branch: triage/bug-186-first-launch-slow-modelcontainer-sync-init
bug: 186
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Bug #186 row + detail entry to `docs/bugs.md`.
No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:
- `VReaderApp.swift:109-113`: `ModelContainer(for: schema, migrationPlan: VReaderMigrationPlan.self, configurations: [modelConfig])` is called synchronously on `@MainActor` inside the app struct `init()`. SwiftData evaluates all 6 schema versions (SchemaV1–SchemaV6 in `VReaderMigrationPlan`) during container creation.
- On a fresh install (every reinstall wipes the SwiftData store), the container must create the entire database schema from scratch — all tables, indexes, migration checks — while the main thread is blocked. This is the direct cause of the first-launch freeze.
- `VReaderApp.swift:226-234`: `LazyDownloadCoordinator` is instantiated and calls `reattachAndReconcile()` via async `Task`. This performs a full DB scan for `.downloading` books at startup and may compound the cold-open cost, though it runs asynchronously and is a secondary factor.
- Confirmed not a duplicate of:
  - Bug #4 (SearchViewModel creation before indexing — search-panel latency)
  - Bug #79 (deferred background indexing — TXT file FTS5 indexing latency)
  - Bug #89 (SQLite WAL mode — persistence actor performance)
  None of those addressed synchronous `ModelContainer` creation on the main thread.
- Severity: Medium. The freeze only occurs on first launch after fresh install or reinstall. Subsequent launches are fast. App is functional; user just has to wait ~several seconds.

## Verdict

ship-as-is — documentation only, no code risk.
