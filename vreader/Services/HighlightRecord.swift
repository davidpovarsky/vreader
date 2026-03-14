// Purpose: Lightweight value type for highlight cross-actor transfer.
// Avoids passing @Model objects across actor boundaries.
//
// @coordinates-with: Highlight.swift, PersistenceActor+Highlights.swift,
//   AnnotationAnchor.swift

import Foundation

/// Lightweight value type representing a highlight for cross-boundary transfer.
struct HighlightRecord: Sendable, Equatable, Identifiable {
    var id: UUID { highlightId }

    let highlightId: UUID
    let locator: Locator
    /// Format-specific anchor for precise range restoration (nil for legacy highlights).
    let anchor: AnnotationAnchor?
    let profileKey: String
    let selectedText: String
    let color: String
    let note: String?
    let createdAt: Date
    let updatedAt: Date
}
