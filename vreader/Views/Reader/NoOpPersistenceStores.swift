// Purpose: No-op persistence implementations for reader notification handlers.
// Used when modelContainer is nil (e.g., preview, test scenarios).
//
// @coordinates-with ReaderNotificationHandlers.swift

import Foundation

/// No-op bookmark store — all operations are silent no-ops.
struct NoOpBookmarkStore: BookmarkPersisting {
    func addBookmark(locator: Locator, title: String?, toBookWithKey key: String) async throws -> BookmarkRecord {
        BookmarkRecord(bookmarkId: UUID(), locator: locator, profileKey: "", title: title, createdAt: Date(), updatedAt: Date())
    }
    func removeBookmark(bookmarkId: UUID) async throws {}
    func fetchBookmarks(forBookWithKey key: String) async throws -> [BookmarkRecord] { [] }
    func isBookmarked(locator: Locator, forBookWithKey key: String) async throws -> Bool { false }
    func updateBookmarkTitle(bookmarkId: UUID, title: String?) async throws {}
}

/// No-op highlight store — all operations are silent no-ops.
struct NoOpHighlightStore: HighlightPersisting {
    func addHighlight(locator: Locator, selectedText: String, color: String, note: String?, toBookWithKey key: String) async throws -> HighlightRecord {
        HighlightRecord(highlightId: UUID(), locator: locator, profileKey: "", selectedText: selectedText, color: color, note: note, createdAt: Date(), updatedAt: Date())
    }
    func removeHighlight(highlightId: UUID) async throws {}
    func updateHighlightNote(highlightId: UUID, note: String?) async throws {}
    func updateHighlightColor(highlightId: UUID, color: String) async throws {}
    func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] { [] }
}

/// No-op annotation store — all operations are silent no-ops.
struct NoOpAnnotationStore: AnnotationPersisting {
    func addAnnotation(locator: Locator, content: String, toBookWithKey key: String) async throws -> AnnotationRecord {
        AnnotationRecord(annotationId: UUID(), locator: locator, profileKey: "", content: content, createdAt: Date(), updatedAt: Date())
    }
    func removeAnnotation(annotationId: UUID) async throws {}
    func updateAnnotation(annotationId: UUID, content: String) async throws {}
    func fetchAnnotations(forBookWithKey key: String) async throws -> [AnnotationRecord] { [] }
}
