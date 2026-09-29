// Purpose: Read-only annotation domain seam for Feature #177 WI-6 tools.

import Foundation

struct AIAnnotationCollection: Sendable {
    let notes: [AnnotationRecord]
    let highlights: [HighlightRecord]
    let bookmarks: [BookmarkRecord]
}

protocol AIAnnotationReading: Sendable {
    func readAnnotations(fingerprintKey: String) async throws -> AIAnnotationCollection
}

struct AIAnnotationReadStoreAdapter: AIAnnotationReading {
    private let annotationStore: any AnnotationPersisting
    private let highlightStore: any HighlightPersisting
    private let bookmarkStore: any BookmarkPersisting

    init(
        annotationStore: any AnnotationPersisting,
        highlightStore: any HighlightPersisting,
        bookmarkStore: any BookmarkPersisting
    ) {
        self.annotationStore = annotationStore
        self.highlightStore = highlightStore
        self.bookmarkStore = bookmarkStore
    }

    func readAnnotations(fingerprintKey: String) async throws -> AIAnnotationCollection {
        async let notes = annotationStore.fetchAnnotations(forBookWithKey: fingerprintKey)
        async let highlights = highlightStore.fetchHighlights(forBookWithKey: fingerprintKey)
        async let bookmarks = bookmarkStore.fetchBookmarks(forBookWithKey: fingerprintKey)
        let values = try await (notes, highlights, bookmarks)
        return AIAnnotationCollection(
            notes: values.0,
            highlights: values.1,
            bookmarks: values.2
        )
    }
}
