// Purpose: Schema version 2 — adds anchor storage to Highlight model.
// The anchor field enables format-specific precise range restoration for
// EPUB, PDF, and TXT/MD annotations.
//
// Changes from V1:
// - Highlight gains `anchorData: Data?` (raw JSON bytes of AnnotationAnchor).
//   Stored as Data? to avoid SwiftData Codable enum decode crashes on legacy rows.
//   Decoded via computed `anchor` property with try? for safe nil fallback.
//
// @coordinates-with: SchemaV1.swift, V1toV2Migration.swift, Highlight.swift,
//   AnnotationAnchor.swift

import Foundation
import SwiftData

/// Schema version 2: adds AnnotationAnchor to Highlight.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Book.self,
            ReadingPosition.self,
            Bookmark.self,
            Highlight.self,
            AnnotationNote.self,
            ReadingSession.self,
            ReadingStats.self,
        ]
    }
}
