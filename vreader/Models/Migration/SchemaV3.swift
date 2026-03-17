// Purpose: Schema version 3 — adds BookCollection model and series fields to Book.
//
// Changes from V2:
// - New BookCollection @Model (name, createdAt, books relationship).
// - Book gains seriesName: String?, seriesIndex: Int?, bookCollections: [BookCollection].
// - All new fields are optional/defaulted, so lightweight migration applies.
//
// @coordinates-with: SchemaV2.swift, BookCollection.swift, Book.swift

import Foundation
import SwiftData

/// Schema version 3: adds BookCollection entity and series fields to Book.
enum SchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Book.self,
            ReadingPosition.self,
            Bookmark.self,
            Highlight.self,
            AnnotationNote.self,
            ReadingSession.self,
            ReadingStats.self,
            BookCollection.self,
        ]
    }
}
