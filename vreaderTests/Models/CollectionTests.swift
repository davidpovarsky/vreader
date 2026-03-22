// Purpose: Tests for BookCollection @Model and Book series/tag/collection features.
// Tests cover model creation, validation, and field defaults.

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("BookCollection Model")
struct BookCollectionModelTests {

    // MARK: - Model Creation

    @Test("init sets name and createdAt")
    func initSetsFields() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let collection = BookCollection(name: "Fiction", createdAt: date)
        #expect(collection.name == "Fiction")
        #expect(collection.createdAt == date)
        #expect(collection.books.isEmpty)
    }

    @Test("init trims whitespace from name")
    func initTrimsWhitespace() {
        let collection = BookCollection(name: "  Sci-Fi  ")
        #expect(collection.name == "Sci-Fi")
    }

    @Test("init truncates long names to 100 characters")
    func initTruncatesLongName() {
        let longName = String(repeating: "a", count: 150)
        let collection = BookCollection(name: longName)
        #expect(collection.name.count == 100)
    }

    @Test("init handles Unicode/CJK names")
    func initHandlesUnicode() {
        let collection = BookCollection(name: "科幻小说收藏")
        #expect(collection.name == "科幻小说收藏")
    }

    @Test("init handles emoji names")
    func initHandlesEmoji() {
        let collection = BookCollection(name: "📚 Books")
        #expect(collection.name == "📚 Books")
    }

    // MARK: - Validation

    @Test("validateName rejects empty string")
    func validateNameRejectsEmpty() {
        #expect(!BookCollection.validateName(""))
    }

    @Test("validateName rejects whitespace-only string")
    func validateNameRejectsWhitespace() {
        #expect(!BookCollection.validateName("   "))
        #expect(!BookCollection.validateName("\t\n"))
    }

    @Test("validateName accepts valid name")
    func validateNameAcceptsValid() {
        #expect(BookCollection.validateName("Fiction"))
        #expect(BookCollection.validateName("科幻"))
        #expect(BookCollection.validateName("a"))
    }
}

@Suite("Book Series Fields")
struct BookSeriesFieldTests {

    static let sampleFP = DocumentFingerprint(
        contentSHA256: "abc123def456abc123def456abc123def456abc123def456abc123def456abcd",
        fileByteCount: 1_048_576,
        format: .epub
    )

    static let sampleProvenance = ImportProvenance(
        source: .filesApp,
        importedAt: Date(timeIntervalSince1970: 1_700_000_000),
        originalURLBookmarkData: nil
    )

    @Test("seriesName and seriesIndex default to nil")
    func seriesFieldsDefaultNil() {
        let book = Book(
            fingerprint: Self.sampleFP,
            title: "Test",
            provenance: Self.sampleProvenance
        )
        #expect(book.seriesName == nil)
        #expect(book.seriesIndex == nil)
    }

    @Test("seriesName and seriesIndex can be set")
    func seriesFieldsCanBeSet() {
        let book = Book(
            fingerprint: Self.sampleFP,
            title: "Test",
            provenance: Self.sampleProvenance
        )
        book.seriesName = "Lord of the Rings"
        book.seriesIndex = 1
        #expect(book.seriesName == "Lord of the Rings")
        #expect(book.seriesIndex == 1)
    }

    @Test("bookCollections defaults to empty")
    func collectionsDefaultEmpty() {
        let book = Book(
            fingerprint: Self.sampleFP,
            title: "Test",
            provenance: Self.sampleProvenance
        )
        #expect(book.bookCollections.isEmpty)
    }
}
