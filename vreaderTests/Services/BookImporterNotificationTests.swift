// Purpose: Tests for Bug #197 — BookImporter posts `.bookDidImport`
// notification after a successful import (and on the duplicate-replace path)
// so library views observing it can refresh without polling. The original
// bug was: incoming-URL imports (Feature #59 / FileURLImportRouter) inserted
// the book into SwiftData but the library view never refreshed because it
// uses an imperative `loadBooks()` array, not a reactive `@Query`. Adding
// this notification gives every import path a free refresh signal.

import Testing
import Foundation
@testable import vreader

/// Captures `.bookDidImport` notifications during the lifetime of an instance.
/// Tests register one BEFORE triggering an import, then check the collected
/// keys after. Concurrent suites in the same test process can also post the
/// notification (BookImporterTests, BookImporterAZW3Tests share
/// NotificationCenter.default), so each test filters the collected keys
/// rather than asserting on a count.
private final class NotificationKeyCollector: @unchecked Sendable {
    private let holder = LockedKeyArray()
    private let token: NSObjectProtocol

    init() {
        let holderRef = holder
        token = NotificationCenter.default.addObserver(
            forName: .bookDidImport, object: nil, queue: nil
        ) { notification in
            if let key = notification.userInfo?["fingerprintKey"] as? String {
                holderRef.append(key)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }

    func contains(_ key: String) -> Bool {
        return holder.contains(key)
    }
}

/// Lock-protected key array shared between the NotificationCenter observer
/// closure (which can fire on any queue) and the test reading the result.
private final class LockedKeyArray: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String] = []

    func append(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        keys.append(key)
    }

    func contains(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return keys.contains(key)
    }
}

@Suite("BookImporter — .bookDidImport notification (bug #197)")
struct BookImporterNotificationTests {

    private func makeTempTxtFile(content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test_\(UUID().uuidString).txt")
        try content.data(using: .utf8)!.write(to: url)
        return url
    }

    private func makeSandboxDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeImporter() async throws -> (BookImporter, MockPersistenceActor, URL) {
        let mock = MockPersistenceActor()
        let sandbox = try makeSandboxDir()
        let importer = BookImporter(
            persistence: mock,
            sandboxBooksDirectory: sandbox
        )
        return (importer, mock, sandbox)
    }

    @Test
    func successfulImport_postsBookDidImportNotification() async throws {
        let unique = UUID().uuidString
        let fileURL = try makeTempTxtFile(content: "successful-\(unique)")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        // Register observer BEFORE the import so the synchronous
        // NotificationCenter.default.post call from BookImporter is captured.
        let collector = NotificationKeyCollector()

        let result = try await importer.importFile(at: fileURL, source: .filesApp)

        // NotificationCenter.default.post is synchronous, so by the time
        // importFile returns the notification has already been delivered to
        // observers added with `queue: nil` (which run synchronously on the
        // posting thread). No sleep needed — the assert reads the lock-
        // protected array directly.
        #expect(collector.contains(result.fingerprintKey),
                "Expected `.bookDidImport` to fire with fingerprintKey \(result.fingerprintKey)")
    }

    @Test
    func duplicateImport_alsoPostsBookDidImportNotification() async throws {
        // Per bug #197 acceptance: importing the same file twice should still
        // surface the row to the user (the import "succeeded" semantically,
        // even though no new row was created). Without this, a user who
        // re-shares an already-imported file via the Share Sheet would see
        // nothing change in the library — confusing.
        let unique = UUID().uuidString
        let fileURL = try makeTempTxtFile(content: "duplicate-\(unique)")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        // First import — establishes the row.
        let first = try await importer.importFile(at: fileURL, source: .filesApp)

        // Register a FRESH collector for the duplicate-path test so we don't
        // mistake the first import's notification for the second one's.
        let collector = NotificationKeyCollector()

        let second = try await importer.importFile(at: fileURL, source: .filesApp)
        #expect(second.isDuplicate, "Second import of identical file must be flagged duplicate")
        #expect(second.fingerprintKey == first.fingerprintKey)
        #expect(collector.contains(first.fingerprintKey),
                "Duplicate-path import must still post `.bookDidImport` so the library refreshes")
    }
}
