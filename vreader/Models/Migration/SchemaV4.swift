// Purpose: Schema version 4 — adds BookSource and ContentReplacementRule models.
//
// Changes from V3:
// - New BookSource @Model (web novel source definitions).
// - New ContentReplacementRule @Model (text replacement rules).
// - Both are independent entities — no relationship changes to existing models.
// - All new fields are optional/defaulted, so lightweight migration applies.
//
// @coordinates-with: SchemaV3.swift, BookSource.swift, ContentReplacementRule.swift

import Foundation
import SwiftData

/// Schema version 4: adds BookSource and ContentReplacementRule entities.
enum SchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

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
            BookSource.self,
            ContentReplacementRule.self,
        ]
    }
}
