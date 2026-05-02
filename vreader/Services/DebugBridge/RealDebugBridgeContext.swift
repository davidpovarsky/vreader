// Purpose: Production handler set behind the vreader-debug:// URL scheme
// (feature #44 DebugBridge, WI-5). Owns dependencies on real app subsystems
// (PersistenceActor for now; importer/active-reader added incrementally) so
// each command performs real work rather than logging. DEBUG-only.
//
// Composition: VReaderApp.init() builds one of these with the same
// dependencies it injects into LibraryViewModel, then installs it on
// DebugBridgeProvider.shared so .onOpenURL dispatches to the real handlers.

#if DEBUG

import Foundation
import OSLog

/// Production DebugBridgeContext. Each handler is a thin wrapper over
/// existing app services so behavior matches what the user-facing UI does
/// (no parallel implementations to drift). Handlers added incrementally
/// across WI-5; un-implemented ones log and no-op.
@MainActor
final class RealDebugBridgeContext: DebugBridgeContext {
    private let persistence: PersistenceActor
    private let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")

    init(persistence: PersistenceActor) {
        self.persistence = persistence
    }

    /// Wipe every book from the library. Idempotent — succeeds on an empty
    /// library. Mirrors `TestSeeder.clearAllBooks`; keeping a separate path
    /// rather than calling that helper directly so test-seeding logic and
    /// debug-bridge logic stay independent.
    func reset() async {
        do {
            let books = try await persistence.fetchAllLibraryBooks()
            for book in books {
                try await persistence.deleteBook(fingerprintKey: book.fingerprintKey)
            }
            log.info("reset: removed \(books.count) book(s)")
        } catch {
            log.error("reset failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Stubs (filled in by later WI-5 commits)

    func seed(fixture: String) async {
        log.info("seed fixture=\(fixture, privacy: .public) — not yet implemented")
    }

    func open(bookId: String, position: String?) async {
        log.info("open bookId=\(bookId, privacy: .public) position=\(position ?? "nil", privacy: .public) — not yet implemented")
    }

    func theme(mode: DebugCommand.ThemeMode, fontSize: Int?) async {
        log.info("theme mode=\(mode.rawValue, privacy: .public) fontSize=\(fontSize.map(String.init) ?? "nil", privacy: .public) — not yet implemented")
    }

    func settle(token: String) async {
        log.info("settle token=\(token, privacy: .public) — not yet implemented")
    }

    func snapshot(dest: String) async {
        log.info("snapshot dest=\(dest, privacy: .public) — not yet implemented")
    }

    func eval(bridge: String, js: String) async {
        log.info("eval bridge=\(bridge, privacy: .public) jsLen=\(js.count) — not yet implemented")
    }
}

#endif
