---
branch: triage/bug-183-txt-search-panel-freeze-main-thread
bug: 183
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Bug #183 row + detail entry to `docs/bugs.md`.
No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:
- `ReaderSearchCoordinator.swift:12`: class is annotated `@MainActor`.
- `ReaderSearchCoordinator.swift:132`: `enqueueBookIndexing` is `private static func` — no
  `nonisolated` keyword → inherits `@MainActor` from the class.
- `ReaderSearchCoordinator.swift:142-143`: `let result = try await extractor.extractWithOffsets(from: fileURL)`
  runs on the main actor.
- `TXTTextExtractor.swift:35-38`: `extractWithOffsets(from:)` is `async` but calls `Self.decodeFile(at:)`
  synchronously (no `Task.detached`, no `await`, no actor hop).
- `TXTTextExtractor.swift:48-56`: `decodeFile(at:)` calls `Data(contentsOf: url, options: .mappedIfSafe)`
  (blocking file I/O) + `TXTService.decodeForDisplayAndSearch()` (encoding detection) — both synchronous.
- `BackgroundIndexingCoordinator.swift:72`: `Task.detached(priority: .background)` is used for FTS5
  indexing only, not for extraction — extraction is already complete by the time the detached task runs.
- Confirmed distinct from #4 (VM startup perf), #79 (deferred indexing), #89 (SQLite open-at-startup):
  none of those bugs addressed moving text extraction off the main thread.

## Verdict

ship-as-is — documentation only, no code risk.
