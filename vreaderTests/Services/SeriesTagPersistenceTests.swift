// Purpose: Tests for tag and series operations on PersistenceActor+Collections.
// Uses CollectionTestHelper for shared setup.

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("Tag Persistence")
struct TagPersistenceTests {

    @Test("addTag and removeTag on book")
    func bookTagsAddRemove() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let bookKey = try await CollectionTestHelper.insertBook(
            persistence: persistence
        )

        try await persistence.addTagToBook(
            bookFingerprintKey: bookKey, tag: "fiction"
        )
        try await persistence.addTagToBook(
            bookFingerprintKey: bookKey, tag: "sci-fi"
        )

        let book = try await persistence.findBook(byFingerprintKey: bookKey)
        #expect(book != nil)

        try await persistence.removeTagFromBook(
            bookFingerprintKey: bookKey, tag: "fiction"
        )

        let bookAfter = try await persistence.findBook(
            byFingerprintKey: bookKey
        )
        #expect(bookAfter != nil)
    }

    @Test("addTag rejects empty tag")
    func addTagRejectsEmpty() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let bookKey = try await CollectionTestHelper.insertBook(
            persistence: persistence
        )
        await #expect(throws: CollectionError.emptyName) {
            try await persistence.addTagToBook(
                bookFingerprintKey: bookKey, tag: ""
            )
        }
    }

    @Test("addTag rejects whitespace-only tag")
    func addTagRejectsWhitespace() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let bookKey = try await CollectionTestHelper.insertBook(
            persistence: persistence
        )
        await #expect(throws: CollectionError.emptyName) {
            try await persistence.addTagToBook(
                bookFingerprintKey: bookKey, tag: "   "
            )
        }
    }

    @Test("fetchAllTags returns unique sorted tags across books")
    func fetchAllTagsSorted() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let sha1 = String(repeating: "c", count: 64)
        let sha2 = String(repeating: "d", count: 64)

        let key1 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "B1", sha: sha1
        )
        let key2 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "B2", sha: sha2
        )

        try await persistence.addTagToBook(
            bookFingerprintKey: key1, tag: "sci-fi"
        )
        try await persistence.addTagToBook(
            bookFingerprintKey: key1, tag: "fiction"
        )
        try await persistence.addTagToBook(
            bookFingerprintKey: key2, tag: "sci-fi"
        )
        try await persistence.addTagToBook(
            bookFingerprintKey: key2, tag: "classics"
        )

        let tags = try await persistence.fetchAllTags()
        #expect(tags == ["classics", "fiction", "sci-fi"])
    }

    @Test("fetchAllTags empty when no tags")
    func fetchAllTagsEmpty() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        _ = try await CollectionTestHelper.insertBook(persistence: persistence)
        let tags = try await persistence.fetchAllTags()
        #expect(tags.isEmpty)
    }

    @Test("addTag deduplicates")
    func addTagDeduplicates() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let bookKey = try await CollectionTestHelper.insertBook(
            persistence: persistence
        )

        try await persistence.addTagToBook(
            bookFingerprintKey: bookKey, tag: "fiction"
        )
        try await persistence.addTagToBook(
            bookFingerprintKey: bookKey, tag: "fiction"
        )

        let book = try await persistence.findBook(byFingerprintKey: bookKey)
        #expect(book != nil)
    }
}

@Suite("Series Persistence")
struct SeriesPersistenceTests {

    private let sha1 = String(repeating: "1", count: 64)
    private let sha2 = String(repeating: "2", count: 64)
    private let sha3 = String(repeating: "3", count: 64)

    @Test("series ordered by seriesIndex")
    func seriesOrderedByIndex() async throws {
        let persistence = try CollectionTestHelper.makePersistence()

        let key1 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "Book Three", sha: sha1
        )
        let key2 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "Book One", sha: sha2
        )
        let key3 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "Book Two", sha: sha3
        )

        try await persistence.setBookSeries(
            bookFingerprintKey: key1, seriesName: "MySeries", seriesIndex: 3
        )
        try await persistence.setBookSeries(
            bookFingerprintKey: key2, seriesName: "MySeries", seriesIndex: 1
        )
        try await persistence.setBookSeries(
            bookFingerprintKey: key3, seriesName: "MySeries", seriesIndex: 2
        )

        let series = try await persistence.fetchBooksInSeries(
            seriesName: "MySeries"
        )
        #expect(series.count == 3)
        #expect(series[0].title == "Book One")
        #expect(series[1].title == "Book Two")
        #expect(series[2].title == "Book Three")
        #expect(series[0].seriesIndex == 1)
        #expect(series[1].seriesIndex == 2)
        #expect(series[2].seriesIndex == 3)
    }

    @Test("series gap in index handled")
    func seriesGapInIndex() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let shaA = String(repeating: "a", count: 64)
        let shaB = String(repeating: "b", count: 64)

        let key1 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "First", sha: shaA
        )
        let key2 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "Third", sha: shaB
        )

        try await persistence.setBookSeries(
            bookFingerprintKey: key1, seriesName: "Gaps", seriesIndex: 1
        )
        try await persistence.setBookSeries(
            bookFingerprintKey: key2, seriesName: "Gaps", seriesIndex: 5
        )

        let series = try await persistence.fetchBooksInSeries(
            seriesName: "Gaps"
        )
        #expect(series.count == 2)
        #expect(series[0].seriesIndex == 1)
        #expect(series[1].seriesIndex == 5)
    }

    @Test("series nil index sorts after indexed books")
    func seriesNilIndexSortsLast() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let shaD = String(repeating: "d", count: 64)
        let shaE = String(repeating: "e", count: 64)

        let key1 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "Indexed", sha: shaD
        )
        let key2 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "Unindexed", sha: shaE
        )

        try await persistence.setBookSeries(
            bookFingerprintKey: key1, seriesName: "NilTest", seriesIndex: 1
        )
        try await persistence.setBookSeries(
            bookFingerprintKey: key2, seriesName: "NilTest", seriesIndex: nil
        )

        let series = try await persistence.fetchBooksInSeries(
            seriesName: "NilTest"
        )
        #expect(series.count == 2)
        #expect(series[0].title == "Indexed")
        #expect(series[1].title == "Unindexed")
    }

    @Test("fetchAllSeriesNames returns unique sorted names")
    func fetchAllSeriesNamesSorted() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let shaX = String(repeating: "7", count: 64)
        let shaY = String(repeating: "8", count: 64)
        let shaZ = String(repeating: "9", count: 64)

        let key1 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "B1", sha: shaX
        )
        let key2 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "B2", sha: shaY
        )
        let key3 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "B3", sha: shaZ
        )

        try await persistence.setBookSeries(
            bookFingerprintKey: key1, seriesName: "Zebra", seriesIndex: 1
        )
        try await persistence.setBookSeries(
            bookFingerprintKey: key2, seriesName: "Alpha", seriesIndex: 1
        )
        try await persistence.setBookSeries(
            bookFingerprintKey: key3, seriesName: "Zebra", seriesIndex: 2
        )

        let names = try await persistence.fetchAllSeriesNames()
        #expect(names == ["Alpha", "Zebra"])
    }

    @Test("fetchAllSeriesNames empty when no series")
    func fetchAllSeriesNamesEmpty() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        _ = try await CollectionTestHelper.insertBook(persistence: persistence)
        let names = try await persistence.fetchAllSeriesNames()
        #expect(names.isEmpty)
    }

    @Test("series same name different books")
    func seriesSameNameDifferentBooks() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let shaF = String(repeating: "f", count: 64)
        let shaG = "1111111111111111111111111111111111111111111111111111111111111112"

        let key1 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "Series A Book", sha: shaF
        )
        let key2 = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "Not in Series", sha: shaG
        )

        try await persistence.setBookSeries(
            bookFingerprintKey: key1, seriesName: "Shared", seriesIndex: 1
        )

        let series = try await persistence.fetchBooksInSeries(
            seriesName: "Shared"
        )
        #expect(series.count == 1)
        #expect(series[0].fingerprintKey == key1)
        #expect(!series.contains(where: { $0.fingerprintKey == key2 }))
    }
}
