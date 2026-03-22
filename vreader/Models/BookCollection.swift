// Purpose: Collection model for organizing books into user-created groups.
// Named BookCollection to avoid conflict with Swift's Collection protocol.
//
// Key decisions:
// - Separate @Model entity (not inline on Book) because collections need
//   their own identity, name, creation date, and many-to-many relationship.
// - Name is validated: non-empty, trimmed, max 100 characters, unique.
// - @Relationship with inverse on Book.bookCollections for bidirectional link.
// - Delete rule .nullify: deleting a collection does NOT delete books.
//
// @coordinates-with: Book.swift, PersistenceActor+Collections.swift

import Foundation
import SwiftData

@Model
final class BookCollection {
    // MARK: - Identity

    /// Unique collection name. Enforced at the application layer
    /// (SwiftData cannot enforce unique on non-primitive Codable).
    var name: String

    /// When the collection was created.
    var createdAt: Date

    // MARK: - Relationships

    /// Books in this collection. Nullify on delete: removing a collection
    /// does not remove its books.
    @Relationship(deleteRule: .nullify, inverse: \Book.bookCollections)
    var books: [Book]

    // MARK: - Init

    init(name: String, createdAt: Date = Date()) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = String(trimmed.prefix(100))
        self.createdAt = createdAt
        self.books = []
    }

    // MARK: - Validation

    /// Validates that the collection name is non-empty after trimming.
    static func validateName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }
}
