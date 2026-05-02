// Purpose: Tests for RealDebugBridgeContext — the production handler set
// behind the vreader-debug:// URL scheme (feature #44 DebugBridge, WI-5).
// Verifies that real handlers mutate real subsystems: SwiftData wipes for
// reset, fixture import for seed, etc.

#if DEBUG

import XCTest
import SwiftData
@testable import vreader

final class RealDebugBridgeContextTests: XCTestCase {

    private var container: ModelContainer!
    private var persistence: PersistenceActor!
    private var importer: BookImporter!
    private var sandboxDir: URL!
    private var fixtureBundleDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema(SchemaV4.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        persistence = PersistenceActor(modelContainer: container)

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DebugBridgeTests-\(UUID().uuidString)", isDirectory: true)
        sandboxDir = temp.appendingPathComponent("sandbox", isDirectory: true)
        fixtureBundleDir = temp.appendingPathComponent("bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixtureBundleDir, withIntermediateDirectories: true)

        importer = BookImporter(persistence: persistence, sandboxBooksDirectory: sandboxDir)
    }

    override func tearDown() async throws {
        if let dir = sandboxDir?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
        importer = nil
        persistence = nil
        container = nil
        sandboxDir = nil
        fixtureBundleDir = nil
        try await super.tearDown()
    }

    /// Writes a fake fixture file into a temp directory and returns a Bundle
    /// rooted at that directory. Bundle.url(forResource:withExtension:) finds
    /// loose files in any directory you point it at.
    private func makeFixtureBundle(name: String, ext: String, contents: String) throws -> Bundle {
        let path = fixtureBundleDir.appendingPathComponent("\(name).\(ext)")
        try contents.data(using: .utf8)!.write(to: path)
        return Bundle(url: fixtureBundleDir)!
    }

    // MARK: - reset

    @MainActor
    func test_reset_wipesAllBooksFromLibrary() async throws {
        _ = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "Book A",
            sha: String(repeating: "a", count: 64)
        )
        _ = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "Book B",
            sha: String(repeating: "b", count: 64)
        )
        let beforeCount = try await persistence.fetchAllLibraryBooks().count
        XCTAssertEqual(beforeCount, 2)

        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        await context.reset()

        let afterCount = try await persistence.fetchAllLibraryBooks().count
        XCTAssertEqual(afterCount, 0, "reset must remove every book")
    }

    @MainActor
    func test_reset_onEmptyLibraryIsIdempotent() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        await context.reset()
        await context.reset()

        let afterCount = try await persistence.fetchAllLibraryBooks().count
        XCTAssertEqual(afterCount, 0)
    }

    // MARK: - seed

    @MainActor
    func test_seed_unknownFixtureName_doesNotImportAndDoesNotThrow() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        await context.seed(fixture: "definitely-not-a-fixture")
        let count = try await persistence.fetchAllLibraryBooks().count
        XCTAssertEqual(count, 0, "no library mutation for unknown fixture")
    }

    @MainActor
    func test_seed_warAndPeace_importsTxtFromBundle() async throws {
        let bundle = try makeFixtureBundle(
            name: "war-and-peace",
            ext: "txt",
            contents: "War and Peace\n\nMinimal fixture text for the seed test.\n"
        )
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            fixtureBundle: bundle
        )

        await context.seed(fixture: "war-and-peace")

        let books = try await persistence.fetchAllLibraryBooks()
        XCTAssertEqual(books.count, 1, "seed must import exactly one book")
        XCTAssertEqual(books.first?.format, "txt")
    }

    @MainActor
    func test_seed_calledTwiceWithSameFixture_doesNotCreateDuplicate() async throws {
        let bundle = try makeFixtureBundle(
            name: "war-and-peace",
            ext: "txt",
            contents: "War and Peace\n\nDeterministic content for fingerprint stability.\n"
        )
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            fixtureBundle: bundle
        )

        await context.seed(fixture: "war-and-peace")
        await context.seed(fixture: "war-and-peace")

        let books = try await persistence.fetchAllLibraryBooks()
        XCTAssertEqual(books.count, 1, "second seed of same fixture must not duplicate")
    }
}

#endif
