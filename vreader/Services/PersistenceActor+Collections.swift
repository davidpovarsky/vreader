// Purpose: Extension adding collection CRUD operations to PersistenceActor.
// Handles create, rename, delete, and book membership for collections.
//
// Key decisions:
// - Name uniqueness enforced at application layer (case-insensitive).
// - Empty/whitespace-only names are rejected with CollectionError.
// - Deleting a collection nullifies the relationship, keeping books intact.
// - Tag operations (add/remove) are on Book directly, not collections.
//
// @coordinates-with: PersistenceActor.swift, BookCollection.swift, Book.swift

import Foundation
import SwiftData

/// Errors specific to collection operations.
enum CollectionError: Error, Sendable, Equatable {
    case emptyName
    case duplicateName(String)
    case collectionNotFound(String)
    case bookNotFound(String)
}

extension PersistenceActor {

    // MARK: - Collection CRUD

    /// Creates a new collection with the given name.
    /// Rejects empty names and duplicate names (case-insensitive).
    func createCollection(name: String) async throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CollectionError.emptyName
        }

        let context = ModelContext(modelContainer)
        let truncated = String(trimmed.prefix(100))

        // Check for duplicate name (case-insensitive)
        let allCollections = try context.fetch(FetchDescriptor<BookCollection>())
        let lowered = truncated.lowercased()
        if allCollections.contains(where: { $0.name.lowercased() == lowered }) {
            throw CollectionError.duplicateName(truncated)
        }

        let collection = BookCollection(name: truncated)
        context.insert(collection)
        try context.save()
        return truncated
    }

    /// Renames an existing collection. Rejects empty names and duplicate names.
    func renameCollection(oldName: String, newName: String) async throws {
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNew.isEmpty else {
            throw CollectionError.emptyName
        }
        let truncatedNew = String(trimmedNew.prefix(100))

        let context = ModelContext(modelContainer)
        let allCollections = try context.fetch(FetchDescriptor<BookCollection>())

        guard let collection = allCollections.first(where: { $0.name == oldName }) else {
            throw CollectionError.collectionNotFound(oldName)
        }

        // Check for duplicate (case-insensitive), excluding the collection being renamed
        let lowered = truncatedNew.lowercased()
        if allCollections.contains(where: {
            $0.name.lowercased() == lowered && $0.name != oldName
        }) {
            throw CollectionError.duplicateName(truncatedNew)
        }

        collection.name = truncatedNew
        try context.save()
    }

    /// Deletes a collection by name. Books in the collection are preserved.
    func deleteCollection(name: String) async throws {
        let context = ModelContext(modelContainer)
        let allCollections = try context.fetch(FetchDescriptor<BookCollection>())

        guard let collection = allCollections.first(where: { $0.name == name }) else {
            throw CollectionError.collectionNotFound(name)
        }

        context.delete(collection)
        try context.save()
    }

    /// Fetches all collections sorted by name.
    func fetchAllCollections() async throws -> [CollectionRecord] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<BookCollection>(
            sortBy: [SortDescriptor(\.name)]
        )
        let collections = try context.fetch(descriptor)

        return collections.map { collection in
            CollectionRecord(
                name: collection.name,
                createdAt: collection.createdAt,
                bookCount: collection.books.count
            )
        }
    }

    // MARK: - Collection Membership

    /// Adds a book to a collection. No-op if already a member.
    func addBookToCollection(
        bookFingerprintKey: String,
        collectionName: String
    ) async throws {
        let context = ModelContext(modelContainer)

        let bookPredicate = #Predicate<Book> { $0.fingerprintKey == bookFingerprintKey }
        var bookDescriptor = FetchDescriptor<Book>(predicate: bookPredicate)
        bookDescriptor.fetchLimit = 1

        guard let book = try context.fetch(bookDescriptor).first else {
            throw CollectionError.bookNotFound(bookFingerprintKey)
        }

        let allCollections = try context.fetch(FetchDescriptor<BookCollection>())
        guard let collection = allCollections.first(
            where: { $0.name == collectionName }
        ) else {
            throw CollectionError.collectionNotFound(collectionName)
        }

        // No-op if already a member
        let key = bookFingerprintKey
        if !collection.books.contains(where: { $0.fingerprintKey == key }) {
            collection.books.append(book)
            try context.save()
        }
    }

    /// Removes a book from a collection. No-op if not a member.
    func removeBookFromCollection(
        bookFingerprintKey: String,
        collectionName: String
    ) async throws {
        let context = ModelContext(modelContainer)

        let allCollections = try context.fetch(FetchDescriptor<BookCollection>())
        guard let collection = allCollections.first(
            where: { $0.name == collectionName }
        ) else {
            throw CollectionError.collectionNotFound(collectionName)
        }

        let key = bookFingerprintKey
        collection.books.removeAll { $0.fingerprintKey == key }
        try context.save()
    }

    /// Fetches fingerprint keys of books in a specific collection.
    func fetchBooksInCollection(name: String) async throws -> [String] {
        let context = ModelContext(modelContainer)
        let allCollections = try context.fetch(FetchDescriptor<BookCollection>())

        guard let collection = allCollections.first(
            where: { $0.name == name }
        ) else {
            throw CollectionError.collectionNotFound(name)
        }

        return collection.books.map(\.fingerprintKey)
    }

    // MARK: - Tag Operations

    /// Adds a tag to a book. Rejects empty tags. Deduplicates.
    func addTagToBook(bookFingerprintKey: String, tag: String) async throws {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CollectionError.emptyName
        }

        let context = ModelContext(modelContainer)
        let key = bookFingerprintKey
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw CollectionError.bookNotFound(bookFingerprintKey)
        }

        if !book.tags.contains(trimmed) {
            book.tags.append(trimmed)
            try context.save()
        }
    }

    /// Removes a tag from a book.
    func removeTagFromBook(bookFingerprintKey: String, tag: String) async throws {
        let context = ModelContext(modelContainer)
        let key = bookFingerprintKey
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw CollectionError.bookNotFound(bookFingerprintKey)
        }

        book.tags.removeAll { $0 == tag }
        try context.save()
    }

    // MARK: - Aggregate Queries

    /// Fetches all unique tags across all books, sorted alphabetically.
    func fetchAllTags() async throws -> [String] {
        let context = ModelContext(modelContainer)
        let allBooks = try context.fetch(FetchDescriptor<Book>())
        var tagSet = Set<String>()
        for book in allBooks {
            for tag in book.tags {
                tagSet.insert(tag)
            }
        }
        return tagSet.sorted()
    }

    /// Fetches all unique series names across all books, sorted alphabetically.
    func fetchAllSeriesNames() async throws -> [String] {
        let context = ModelContext(modelContainer)
        let allBooks = try context.fetch(FetchDescriptor<Book>())
        var nameSet = Set<String>()
        for book in allBooks {
            if let name = book.seriesName, !name.isEmpty {
                nameSet.insert(name)
            }
        }
        return nameSet.sorted()
    }

    // MARK: - Series Operations

    /// Sets the series info for a book.
    func setBookSeries(
        bookFingerprintKey: String,
        seriesName: String?,
        seriesIndex: Int?
    ) async throws {
        let context = ModelContext(modelContainer)
        let key = bookFingerprintKey
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw CollectionError.bookNotFound(bookFingerprintKey)
        }

        book.seriesName = seriesName
        book.seriesIndex = seriesIndex
        try context.save()
    }

    /// Fetches books in a series, ordered by seriesIndex.
    /// Books with nil seriesIndex sort after those with an index.
    func fetchBooksInSeries(
        seriesName: String
    ) async throws -> [BookSeriesRecord] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Book>()
        let allBooks = try context.fetch(descriptor)

        let seriesBooks = allBooks
            .filter { $0.seriesName == seriesName }
            .sorted { lhs, rhs in
                switch (lhs.seriesIndex, rhs.seriesIndex) {
                case let (.some(l), .some(r)): return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.title < rhs.title
                }
            }

        return seriesBooks.map {
            BookSeriesRecord(
                fingerprintKey: $0.fingerprintKey,
                title: $0.title,
                seriesIndex: $0.seriesIndex
            )
        }
    }
}

// MARK: - Value Types

/// Lightweight value type for collection display.
struct CollectionRecord: Sendable, Equatable {
    let name: String
    let createdAt: Date
    let bookCount: Int
}

/// Lightweight value type for series book display.
struct BookSeriesRecord: Sendable, Equatable {
    let fingerprintKey: String
    let title: String
    let seriesIndex: Int?
}
