// Purpose: Coordinates annotation mutations (notes, highlights, bookmarks) through existing domain protocols.
// Validates locators and posts readerAnnotationsDidChange on successful completion.

import Foundation

actor AIAnnotationMutationCoordinator {
    private let annotationPersisting: any AnnotationPersisting
    private let highlightPersisting: any HighlightPersisting
    private let bookmarkPersisting: any BookmarkPersisting

    init(
        annotationPersisting: any AnnotationPersisting,
        highlightPersisting: any HighlightPersisting,
        bookmarkPersisting: any BookmarkPersisting
    ) {
        self.annotationPersisting = annotationPersisting
        self.highlightPersisting = highlightPersisting
        self.bookmarkPersisting = bookmarkPersisting
    }

    // MARK: - Notes

    func createNote(
        bookKey: String,
        locator: Locator,
        content: String
    ) async throws -> AnnotationRecord {
        try Task.checkCancellation()
        let record = try await annotationPersisting.addAnnotation(
            locator: locator,
            content: content,
            toBookWithKey: bookKey
        )
        postChangeNotification()
        return record
    }

    func editNote(annotationID: UUID, content: String) async throws {
        try Task.checkCancellation()
        try await annotationPersisting.updateAnnotation(annotationId: annotationID, content: content)
        postChangeNotification()
    }

    func deleteNote(annotationID: UUID) async throws {
        try Task.checkCancellation()
        try await annotationPersisting.removeAnnotation(annotationId: annotationID)
        postChangeNotification()
    }

    // MARK: - Highlights

    func addHighlight(
        bookKey: String,
        locator: Locator,
        selectedText: String,
        color: String = "yellow",
        note: String? = nil
    ) async throws -> HighlightRecord {
        try Task.checkCancellation()
        let record = try await highlightPersisting.addHighlight(
            locator: locator,
            selectedText: selectedText,
            color: color,
            note: note,
            toBookWithKey: bookKey
        )
        postChangeNotification()
        return record
    }

    func updateHighlight(
        highlightID: UUID,
        note: String? = nil,
        color: String? = nil
    ) async throws {
        try Task.checkCancellation()
        if let note {
            try await highlightPersisting.updateHighlightNote(highlightId: highlightID, note: note)
        }
        if let color {
            try await highlightPersisting.updateHighlightColor(highlightId: highlightID, color: color)
        }
        postChangeNotification()
    }

    func removeHighlight(highlightID: UUID) async throws {
        try Task.checkCancellation()
        try await highlightPersisting.removeHighlight(highlightId: highlightID)
        postChangeNotification()
    }

    // MARK: - Bookmarks

    func addBookmark(
        bookKey: String,
        locator: Locator,
        title: String? = nil
    ) async throws -> BookmarkRecord {
        try Task.checkCancellation()
        let record = try await bookmarkPersisting.addBookmark(
            locator: locator,
            title: title,
            toBookWithKey: bookKey
        )
        postChangeNotification()
        return record
    }

    func updateBookmark(bookmarkID: UUID, title: String?) async throws {
        try Task.checkCancellation()
        try await bookmarkPersisting.updateBookmarkTitle(bookmarkId: bookmarkID, title: title)
        postChangeNotification()
    }

    func removeBookmark(bookmarkID: UUID) async throws {
        try Task.checkCancellation()
        try await bookmarkPersisting.removeBookmark(bookmarkId: bookmarkID)
        postChangeNotification()
    }

    private func postChangeNotification() {
        NotificationCenter.default.post(name: .readerAnnotationsDidChange, object: nil)
    }
}
