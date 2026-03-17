// Purpose: Imports VReader JSON annotation exports into the persistence layer.
// Deduplicates by annotation ID, dispatches to mock-injectable stores,
// and reports progress via callback.
//
// @coordinates-with: VReaderAnnotationParser.swift, HighlightPersisting.swift,
//   BookmarkPersisting.swift, AnnotationPersisting.swift

import Foundation

/// Result of an annotation import operation.
struct AnnotationImportResult: Sendable, Equatable {
    let importedCount: Int
    let skippedCount: Int
}

/// Imports VReader JSON annotation exports into the persistence layer.
struct AnnotationImporter: Sendable {
    private let highlightStore: any HighlightPersisting
    private let bookmarkStore: any BookmarkPersisting
    private let annotationStore: any AnnotationPersisting
    private let existingAnnotationIds: Set<UUID>

    init(
        highlightStore: any HighlightPersisting,
        bookmarkStore: any BookmarkPersisting,
        annotationStore: any AnnotationPersisting,
        existingAnnotationIds: Set<UUID> = []
    ) {
        self.highlightStore = highlightStore
        self.bookmarkStore = bookmarkStore
        self.annotationStore = annotationStore
        self.existingAnnotationIds = existingAnnotationIds
    }

    /// Imports annotations from VReader JSON data.
    /// - Parameters:
    ///   - data: JSON data in VReader export format.
    ///   - bookFingerprintKey: The canonical key of the book to import into.
    ///   - onProgress: Optional progress callback (0.0 to 1.0).
    /// - Returns: Import result with counts.
    /// - Throws: `AnnotationImportError` on parse failure.
    func importJSON(
        data: Data,
        bookFingerprintKey: String,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> AnnotationImportResult {
        let payload = try VReaderAnnotationParser.parse(data: data)
        let annotations = payload.annotations
        let total = annotations.count

        guard total > 0 else {
            return AnnotationImportResult(importedCount: 0, skippedCount: 0)
        }

        // Build a minimal locator for imported annotations.
        // The fingerprint key encodes format:sha256:size, which we parse back.
        guard let fingerprint = DocumentFingerprint(canonicalKey: bookFingerprintKey) else {
            throw AnnotationImportError.invalidJSON("Invalid book fingerprint key: \(bookFingerprintKey)")
        }

        var importedCount = 0
        var skippedCount = 0

        for (index, annotation) in annotations.enumerated() {
            if existingAnnotationIds.contains(annotation.id) {
                skippedCount += 1
            } else {
                try await importSingle(annotation, fingerprint: fingerprint, bookKey: bookFingerprintKey)
                importedCount += 1
            }

            let progress = Double(index + 1) / Double(total)
            onProgress?(progress)
        }

        return AnnotationImportResult(importedCount: importedCount, skippedCount: skippedCount)
    }

    // MARK: - Private

    /// Imports a single annotation into the appropriate store.
    private func importSingle(
        _ annotation: ExportedAnnotation,
        fingerprint: DocumentFingerprint,
        bookKey: String
    ) async throws {
        // Build a locator from the fingerprint. Use the annotation's ID as a
        // textQuote disambiguator so the store's locator-based dedup doesn't
        // collapse distinct imported annotations into one.
        let locator = Locator(
            bookFingerprint: fingerprint,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: annotation.id.uuidString, textContextBefore: nil, textContextAfter: nil
        )

        switch annotation.type {
        case .highlight:
            _ = try await highlightStore.addHighlight(
                locator: locator,
                selectedText: annotation.selectedText ?? "",
                color: annotation.color ?? "yellow",
                note: annotation.note,
                toBookWithKey: bookKey
            )

        case .bookmark:
            _ = try await bookmarkStore.addBookmark(
                locator: locator,
                title: annotation.title,
                toBookWithKey: bookKey
            )

        case .note:
            _ = try await annotationStore.addAnnotation(
                locator: locator,
                content: annotation.note ?? "",
                toBookWithKey: bookKey
            )
        }
    }
}
