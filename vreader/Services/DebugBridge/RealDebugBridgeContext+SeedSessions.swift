// Purpose: `seed-sessions` command handler for the vreader-debug:// URL scheme
// (Bug #263). Seeds synthetic `ReadingSession` rows so the reading dashboard
// (Feature #58) renders non-zero per-window totals CU-free — the harness can
// otherwise seed only books, leaving the dashboard all-zero.
//
// Why this is a separate extension file:
//   Mirrors the per-command split (provider / present / ai handlers each have
//   their own +X.swift). The parent `RealDebugBridgeContext.swift` is already
//   near the 300-line guideline; keeping this handler here avoids growing it.
//
// DEBUG-only — entire file compiled out of Release builds.
//
// @coordinates-with: DebugCommand.swift (seedSessions parsing),
//   DebugBridge.swift (dispatcher + protocol), RealDebugBridgeContext.swift
//   (deps), PersistenceActor+Stats.swift (the seedSyntheticReadingSessions seam).

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Bug #263 — seed synthetic `ReadingSession` rows so the reading
    /// dashboard (Feature #58) renders non-zero per-window totals CU-free.
    ///
    /// Parses `bookFingerprintKey` into a `DocumentFingerprint` (failing
    /// loudly with `invalidFingerprintKey` if it isn't a canonical
    /// `format:sha256:byteCount` key — that's what `ReadingSession` needs to
    /// store), then delegates the deterministic session spread + the
    /// `ReadingStats` refresh to `PersistenceActor.seedSyntheticReadingSessions`.
    /// That seam inserts the rows through the same `ModelContext`/`ReadingSession`
    /// path the production session store uses, so the dashboard aggregator
    /// reads them through its normal query — there is no parallel persistence
    /// path. Unlike `open`/`highlight`, this command does NOT require an
    /// active reader: the dashboard reads persisted state, so seeding then
    /// opening the dashboard suffices.
    func seedReadingSessions(bookFingerprintKey: String, secondsPerSession: Int) async throws {
        guard let fingerprint = DocumentFingerprint(canonicalKey: bookFingerprintKey) else {
            throw DebugBridgeContextError.invalidFingerprintKey(bookFingerprintKey)
        }
        let inserted = try await persistence.seedSyntheticReadingSessions(
            bookFingerprint: fingerprint,
            secondsPerSession: secondsPerSession
        )
        NotificationCenter.default.post(name: .debugBridgeLibraryChanged, object: nil)
        log.info(
            "seed-sessions: inserted \(inserted) synthetic session(s) for key=\(bookFingerprintKey, privacy: .public) seconds=\(secondsPerSession)"
        )
    }
}

#endif
