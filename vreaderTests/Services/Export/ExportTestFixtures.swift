// Purpose: Shared test fixtures for annotation export tests.
//
// @coordinates-with: AnnotationExporterTests.swift, MarkdownExportTests.swift,
//   JSONExportTests.swift

import Foundation
@testable import vreader

/// Shared fixtures for annotation export test suites.
enum ExportTestFixtures {

    static let fp = DocumentFingerprint(
        contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        fileByteCount: 2048,
        format: .epub
    )

    static func locator(href: String? = nil) -> Locator {
        Locator(
            bookFingerprint: fp,
            href: href, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func makeHighlight(
        id: UUID = UUID(),
        href: String? = nil,
        text: String = "Sample highlight",
        color: String = "yellow",
        note: String? = nil,
        createdAt: Date = fixedDate,
        updatedAt: Date = fixedDate
    ) -> HighlightRecord {
        HighlightRecord(
            highlightId: id,
            locator: locator(href: href),
            anchor: nil,
            profileKey: "test-key",
            selectedText: text,
            color: color,
            note: note,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func makeBookmark(
        id: UUID = UUID(),
        href: String? = nil,
        title: String? = nil,
        createdAt: Date = fixedDate,
        updatedAt: Date = fixedDate
    ) -> BookmarkRecord {
        BookmarkRecord(
            bookmarkId: id,
            locator: locator(href: href),
            profileKey: "test-key",
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func makeAnnotation(
        id: UUID = UUID(),
        href: String? = nil,
        content: String = "A note",
        createdAt: Date = fixedDate,
        updatedAt: Date = fixedDate
    ) -> AnnotationRecord {
        AnnotationRecord(
            annotationId: id,
            locator: locator(href: href),
            profileKey: "test-key",
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static let chapterMap: [String: String] = [
        "chapter1.xhtml": "Chapter 1: Introduction",
        "chapter2.xhtml": "Chapter 2: Methods",
    ]
}
