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
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

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

        // Unique UserDefaults suite per test so theme tests don't pollute global state
        // or each other.
        defaultsSuiteName = "DebugBridgeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() async throws {
        if let dir = sandboxDir?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
        if let suite = defaultsSuiteName {
            UserDefaults().removePersistentDomain(forName: suite)
        }
        importer = nil
        persistence = nil
        container = nil
        sandboxDir = nil
        fixtureBundleDir = nil
        defaults = nil
        defaultsSuiteName = nil
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
        try await context.reset()

        let afterCount = try await persistence.fetchAllLibraryBooks().count
        XCTAssertEqual(afterCount, 0, "reset must remove every book")
    }

    @MainActor
    func test_reset_onEmptyLibraryIsIdempotent() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        try await context.reset()
        try await context.reset()

        let afterCount = try await persistence.fetchAllLibraryBooks().count
        XCTAssertEqual(afterCount, 0)
    }

    // MARK: - seed

    @MainActor
    func test_seed_unknownFixtureName_throwsAndDoesNotImport() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        do {
            try await context.seed(fixture: "definitely-not-a-fixture")
            XCTFail("expected unknownFixture error")
        } catch DebugBridgeContextError.unknownFixture(let name) {
            XCTAssertEqual(name, "definitely-not-a-fixture")
        }
        let count = try await persistence.fetchAllLibraryBooks().count
        XCTAssertEqual(count, 0, "no library mutation for unknown fixture")
    }

    @MainActor
    func test_seed_resourceMissing_throwsAndDoesNotImport() async throws {
        // Use a bundle that doesn't have the war-and-peace fixture in it
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            fixtureBundle: Bundle(url: fixtureBundleDir)!
        )
        do {
            try await context.seed(fixture: "war-and-peace")
            XCTFail("expected fixtureResourceMissing error")
        } catch DebugBridgeContextError.fixtureResourceMissing {
            // expected
        }
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

        try await context.seed(fixture: "war-and-peace")

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

        try await context.seed(fixture: "war-and-peace")
        try await context.seed(fixture: "war-and-peace")

        let books = try await persistence.fetchAllLibraryBooks()
        XCTAssertEqual(books.count, 1, "second seed of same fixture must not duplicate")
    }

    // MARK: - error propagation through DebugBridge.lastError

    @MainActor
    func test_unknownFixture_setsLastErrorOnBridge() async {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://seed?fixture=missing")!)

        guard case DebugBridgeContextError.unknownFixture? = bridge.lastError as? DebugBridgeContextError else {
            XCTFail("expected unknownFixture in lastError, got \(String(describing: bridge.lastError))")
            return
        }
    }

    @MainActor
    func test_successfulCommand_clearsLastError() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://seed?fixture=missing")!)
        XCTAssertNotNil(bridge.lastError)

        await bridge.handle(URL(string: "vreader-debug://reset")!)
        XCTAssertNil(bridge.lastError, "successful dispatch must clear lastError")
    }

    // MARK: - theme

    @MainActor
    func test_theme_darkModeSetsThemeInUserDefaults() async throws {
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.theme(mode: .dark, fontSize: nil)

        let store = ReaderSettingsStore(defaults: defaults)
        XCTAssertEqual(store.theme, .dark)
    }

    @MainActor
    func test_theme_lightModeSetsThemeInUserDefaults() async throws {
        // Pre-set to dark so we can verify mode=light flips it back
        let pre = ReaderSettingsStore(defaults: defaults)
        pre.theme = .dark

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.theme(mode: .light, fontSize: nil)

        let store = ReaderSettingsStore(defaults: defaults)
        XCTAssertEqual(store.theme, .light)
    }

    @MainActor
    func test_theme_fontSizeIsPersisted() async throws {
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.theme(mode: .dark, fontSize: 22)

        let store = ReaderSettingsStore(defaults: defaults)
        XCTAssertEqual(store.typography.fontSize, 22.0, accuracy: 0.001)
    }

    @MainActor
    func test_theme_nilFontSizeLeavesExistingFontSizeUnchanged() async throws {
        let pre = ReaderSettingsStore(defaults: defaults)
        var typography = pre.typography
        typography.fontSize = 19.0
        pre.typography = typography

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.theme(mode: .light, fontSize: nil)

        let store = ReaderSettingsStore(defaults: defaults)
        XCTAssertEqual(store.typography.fontSize, 19.0, accuracy: 0.001, "nil fontSize should not overwrite")
    }
}

#endif
