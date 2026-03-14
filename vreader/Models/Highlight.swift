// Purpose: User-created text highlight spanning a range in a book.
// Uses Locator with charRangeStartUTF16/charRangeEndUTF16 for TXT,
// or href+CFI for EPUB. Optionally carries an AnnotationAnchor for
// format-specific precise range restoration (SchemaV2).
//
// @coordinates-with: AnnotationAnchor.swift, HighlightRecord.swift,
//   PersistenceActor+Highlights.swift

import Foundation
import SwiftData

@Model
final class Highlight {
    @Attribute(.unique) var highlightId: UUID

    /// Primitive sync key.
    private(set) var profileKey: String

    /// Locator marking the highlight range start (and range via charRange fields).
    /// Mutate via `updateLocator(_:)` — SwiftData `didSet` is unreliable.
    private(set) var locator: Locator

    /// Format-specific anchor for precise range restoration.
    /// Optional — nil for pre-SchemaV2 highlights (backward compatibility).
    /// Stored as a JSON blob by SwiftData via Codable conformance.
    private(set) var anchor: AnnotationAnchor?

    /// The highlighted text content.
    var selectedText: String

    /// User-chosen color name or hex.
    var color: String

    var note: String?
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Explicit Sync

    /// Updates the locator and syncs the derived profileKey.
    /// Use this instead of setting `locator` directly, because
    /// SwiftData @Model classes do not reliably fire `didSet` observers.
    func updateLocator(_ newLocator: Locator) {
        locator = newLocator
        profileKey = "\(newLocator.bookFingerprint.canonicalKey):\(newLocator.canonicalHash)"
    }

    /// Updates the anchor for precise range restoration.
    /// Use this instead of setting `anchor` directly — SwiftData `didSet` is unreliable.
    func updateAnchor(_ newAnchor: AnnotationAnchor?) {
        anchor = newAnchor
        updatedAt = Date()
    }

    // MARK: - Relationship

    var book: Book?

    // MARK: - Init

    init(
        highlightId: UUID = UUID(),
        locator: Locator,
        selectedText: String,
        color: String = "yellow",
        note: String? = nil,
        anchor: AnnotationAnchor? = nil,
        createdAt: Date = Date()
    ) {
        self.highlightId = highlightId
        self.profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
        self.locator = locator
        self.anchor = anchor
        self.selectedText = selectedText
        self.color = color
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
