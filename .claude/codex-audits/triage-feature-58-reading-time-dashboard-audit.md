---
branch: triage/feature-58-reading-time-dashboard
feature: 58
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Feature #58 row to `docs/features.md`.
No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:

**Existing infrastructure** (the feature builds on, not duplicates):
- `vreader/Models/ReadingSession.swift`: SwiftData `@Model` — `sessionId`, `bookFingerprintKey`, `bookFingerprint`, `startedAt`, `endedAt`, `durationSeconds`, `pagesRead`, `wordsRead`, `isRecovered`. Sessions are tracked per-book with start/end timestamps and duration.
- `vreader/Models/ReadingStats.swift`: SwiftData `@Model` — `bookFingerprintKey` (unique), `bookFingerprint`, `totalReadingSeconds`, `sessionCount`, `lastReadAt`, `averagePagesPerHour`, `averageWordsPerMinute`, `totalPagesRead`, `totalWordsRead`, `longestSessionSeconds`. One stats record per book, recomputed from sessions.
- `vreader/Services/ReadingSessionTracker.swift` (323 lines): tracks the current session, saves on app background / book close, recovers from crashes.
- `vreader/Utils/ReadingTimeFormatter.swift` (87 lines): formats `Int` seconds → `"1h 23m"` / `"4m"` style strings.
- `vreader/Models/LibrarySortOrder.swift`: already has `case totalReadingTime` with display name `"Reading Time"`.

**Confirmed gaps** (what feature #58 must add):
- No `*Dashboard*View*` or `*Stats*View*` SwiftUI file anywhere in `vreader/Views/`.
- No time-window aggregator service — `ReadingStats` exposes lifetime totals only, not windowed.
- `BackupDataCollector.swift` covers Annotations, Positions, Settings, Collections, BookSources, PerBookSettings, ReplacementRules — but NOT `ReadingSession` or `ReadingStats`. Same gap in `BackupDataRestorer`.
- CloudKit mirror exists for sessions (`SyncReadingSessionRecord` in `SyncRecordDTOs.swift`, `VRReadingSession` CKRecord mapping at `CloudKitRecordMapper.swift:198-202`), but WebDAV does not. Stats are lost on restore-to-fresh-device for users on WebDAV.
- No per-book aggregated notes/highlights counts surface — `PersistenceActor.fetchAnnotations(forBookWithKey:)` and `.fetchHighlights(forBookWithKey:)` are queryable per-book but never rolled up into a stats view.
- Not a duplicate of feature #6 (Library view preferences) — sort orders include `totalReadingTime` but no dashboard view.
- Not a duplicate of feature #29 (WebDAV backup, VERIFIED) — that feature backs up annotations/positions/settings; this extends the payload to include sessions/stats.
- Not a duplicate of feature #10 (iCloud backup, VERIFIED) — iCloud backup via CloudKit includes sessions; this brings parity to WebDAV.

## Verdict

ship-as-is — documentation only, no code risk. Status moves to `PLANNED` only via the `/feature-workflow` Gate 1 (Plan) + Gate 2 (Independent Plan Audit) sequence.
