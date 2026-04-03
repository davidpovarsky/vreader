// Purpose: Tests for cover lifecycle — cleanup on book delete and rollback on
// import failure. Verifies WI-0 of the cover image extraction plan.
//
// @coordinates-with: PersistenceActor+Library.swift, BookImporter.swift, CustomCoverStore.swift

import Testing
import UIKit
@testable import vreader

@Suite("Cover Lifecycle")
struct CoverLifecycleTests {

    // MARK: - Helpers

    private func makeTestImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format)
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }

    private func makeTempTxtFile(content: String = "Hello cover lifecycle") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("cover_test_\(UUID().uuidString).txt")
        try content.data(using: .utf8)!.write(to: url)
        return url
    }

    private func makeSandboxDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes the cover from the default CustomCoverStore location (cleanup after tests).
    private func cleanupCover(for key: String) {
        try? CustomCoverStore.removeCover(for: key)
    }

    // MARK: - Delete Book Removes Cover

    @Test func deleteBook_removesCoverFromStore() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        defer { cleanupCover(for: key) }

        // Save a cover for this book (using default app support directory)
        let image = makeTestImage()
        try CustomCoverStore.saveCover(image, for: key)
        #expect(CustomCoverStore.hasCover(for: key), "Precondition: cover should exist before delete")

        // Delete the book
        try await persistence.deleteBook(fingerprintKey: key)

        // Cover should be removed
        #expect(!CustomCoverStore.hasCover(for: key), "Cover should be removed after book delete")
    }

    @Test func deleteBook_noCrashWhenNoCoverExists() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)

        // Verify no cover exists
        #expect(!CustomCoverStore.hasCover(for: key), "Precondition: no cover should exist")

        // Delete should succeed without crash
        try await persistence.deleteBook(fingerprintKey: key)
    }

    // MARK: - Import Failure Rollback

    @Test func importFailure_cleansUpOrphanCover() async throws {
        let fileURL = try makeTempTxtFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let sandbox = try makeSandboxDir()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        // First: do a successful import to learn the fingerprintKey
        let successMock = MockPersistenceActor()
        let successImporter = BookImporter(
            persistence: successMock,
            sandboxBooksDirectory: sandbox
        )
        let successResult = try await successImporter.importFile(at: fileURL, source: .filesApp)
        let fingerprintKey = successResult.fingerprintKey
        defer { cleanupCover(for: fingerprintKey) }

        // Now save a cover for this key (simulating WI-2 cover extraction)
        let image = makeTestImage()
        try CustomCoverStore.saveCover(image, for: fingerprintKey)
        #expect(CustomCoverStore.hasCover(for: fingerprintKey), "Precondition: cover should exist")

        // Set up a new import with a mock that fails on insert
        let failMock = MockPersistenceActor()
        await failMock.setInsertError(ImportError.persistenceFailed)
        let failSandbox = try makeSandboxDir()
        defer { try? FileManager.default.removeItem(at: failSandbox) }
        let failImporter = BookImporter(
            persistence: failMock,
            sandboxBooksDirectory: failSandbox
        )

        // Import should fail
        do {
            _ = try await failImporter.importFile(at: fileURL, source: .filesApp)
            Issue.record("Expected import to fail with persistenceFailed")
        } catch {
            // Expected failure
        }

        // Cover should be cleaned up
        #expect(!CustomCoverStore.hasCover(for: fingerprintKey),
                "Orphan cover should be removed after import failure")
    }
}