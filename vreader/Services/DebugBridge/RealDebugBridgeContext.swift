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
    private let importer: BookImporting
    /// Bundle that holds DEBUG fixture resources. Defaults to `Bundle.main`;
    /// tests inject a custom bundle so they don't depend on app installation.
    private let fixtureBundle: Bundle
    private let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")

    init(
        persistence: PersistenceActor,
        importer: BookImporting,
        fixtureBundle: Bundle = .main
    ) {
        self.persistence = persistence
        self.importer = importer
        self.fixtureBundle = fixtureBundle
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

    /// Import a bundled fixture book by name. Idempotent — if a book with
    /// the same fingerprint already exists in the library, the importer
    /// short-circuits without creating a duplicate.
    /// Errors (unknown fixture, missing bundle resource, import failure)
    /// are logged and swallowed; the bridge stays usable for the next
    /// command. WI-5 future work may surface these via lastError on the
    /// snapshot.
    func seed(fixture: String) async {
        guard let entry = DebugFixtureCatalog.find(name: fixture) else {
            log.error("seed: unknown fixture \(fixture, privacy: .public)")
            return
        }
        guard let url = fixtureBundle.url(
            forResource: entry.resourceName,
            withExtension: entry.resourceExtension
        ) else {
            log.error("seed: fixture resource missing in bundle: \(entry.resourceName, privacy: .public).\(entry.resourceExtension, privacy: .public)")
            return
        }
        do {
            let result = try await importer.importFile(at: url, source: .localCopy)
            log.info("seed: imported \(entry.name, privacy: .public) → key=\(result.fingerprintKey, privacy: .public) duplicate=\(result.isDuplicate)")
        } catch {
            log.error("seed: import failed for \(entry.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
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
