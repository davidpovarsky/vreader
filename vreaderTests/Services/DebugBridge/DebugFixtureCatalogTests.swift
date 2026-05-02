// Purpose: Tests for DebugFixtureCatalog — the static list of fixture books
// available to the vreader-debug://seed command (feature #44 DebugBridge).
// Verifies catalog entries by name, format, and unknown-name behavior.

#if DEBUG

import XCTest
@testable import vreader

final class DebugFixtureCatalogTests: XCTestCase {

    func test_all_returnsKnownFixtureNames() {
        let names = DebugFixtureCatalog.all().map { $0.name }
        XCTAssertEqual(Set(names), ["alice", "war-and-peace", "sample-azw3", "sample-pdf"])
    }

    func test_find_byName_returnsMatchingFixture() throws {
        let alice = try XCTUnwrap(DebugFixtureCatalog.find(name: "alice"))
        XCTAssertEqual(alice.name, "alice")
        XCTAssertEqual(alice.format, .epub)
        XCTAssertEqual(alice.resourceName, "alice")
        XCTAssertEqual(alice.resourceExtension, "epub")
    }

    func test_find_unknownName_returnsNil() {
        XCTAssertNil(DebugFixtureCatalog.find(name: "definitely-not-a-fixture"))
    }

    func test_find_emptyName_returnsNil() {
        XCTAssertNil(DebugFixtureCatalog.find(name: ""))
    }

    func test_all_entriesHaveDistinctNames() {
        let names = DebugFixtureCatalog.all().map { $0.name }
        XCTAssertEqual(names.count, Set(names).count, "fixture names must be unique")
    }

    func test_all_entriesHaveValidFormatAndResource() {
        for fixture in DebugFixtureCatalog.all() {
            XCTAssertFalse(fixture.name.isEmpty, "name empty for \(fixture)")
            XCTAssertFalse(fixture.resourceName.isEmpty, "resourceName empty for \(fixture)")
            XCTAssertFalse(fixture.resourceExtension.isEmpty, "resourceExtension empty for \(fixture)")
        }
    }

    func test_textFixtureCatalogedAsTxtFormat() throws {
        let entry = try XCTUnwrap(DebugFixtureCatalog.find(name: "war-and-peace"))
        XCTAssertEqual(entry.format, .txt)
        XCTAssertEqual(entry.resourceExtension, "txt")
    }

    func test_pdfFixtureCatalogedAsPdfFormat() throws {
        let pdf = try XCTUnwrap(DebugFixtureCatalog.find(name: "sample-pdf"))
        XCTAssertEqual(pdf.format, .pdf)
        XCTAssertEqual(pdf.resourceExtension, "pdf")
    }

    func test_azw3FixtureCatalogedAsAzw3Format() throws {
        let entry = try XCTUnwrap(DebugFixtureCatalog.find(name: "sample-azw3"))
        XCTAssertEqual(entry.format, .azw3)
        XCTAssertEqual(entry.resourceExtension, "azw3")
    }
}

#endif
