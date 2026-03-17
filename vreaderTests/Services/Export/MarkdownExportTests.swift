// Purpose: Tests for MarkdownExportFormatter — formatting, grouping, edge cases.
//
// @coordinates-with: MarkdownExportFormatter.swift, ExportTestFixtures.swift

import Testing
import Foundation
@testable import vreader

private typealias F = ExportTestFixtures

@Suite("MarkdownExportFormatter")
struct MarkdownExportTests {

    // MARK: - Book Title

    @Test func includesBookTitle() throws {
        let payload = AnnotationExporter.buildPayload(
            highlights: [F.makeHighlight()], bookmarks: [], notes: [],
            bookTitle: "My Book Title", bookAuthor: "John Doe"
        )
        let md = try formatMarkdown(payload)
        #expect(md.contains("# My Book Title"))
        #expect(md.contains("*by John Doe*"))
    }

    @Test func noAuthor_omitsAuthorLine() throws {
        let payload = AnnotationExporter.buildPayload(
            highlights: [F.makeHighlight()], bookmarks: [], notes: [],
            bookTitle: "No Author Book", bookAuthor: nil
        )
        let md = try formatMarkdown(payload)
        #expect(md.contains("# No Author Book"))
        #expect(!md.contains("*by"))
    }

    // MARK: - Chapter Grouping

    @Test func highlightsGroupedByChapter() throws {
        let h1 = F.makeHighlight(href: "chapter1.xhtml", text: "First highlight")
        let h2 = F.makeHighlight(href: "chapter2.xhtml", text: "Second highlight")
        let h3 = F.makeHighlight(href: "chapter1.xhtml", text: "Another in ch1")

        let payload = AnnotationExporter.buildPayload(
            highlights: [h1, h2, h3], bookmarks: [], notes: [],
            bookTitle: "Grouped Book", bookAuthor: nil,
            chapterMap: F.chapterMap
        )
        let md = try formatMarkdown(payload)

        #expect(md.contains("## Chapter 1: Introduction"))
        #expect(md.contains("## Chapter 2: Methods"))
        #expect(md.contains("> First highlight"))
        #expect(md.contains("> Second highlight"))
        #expect(md.contains("> Another in ch1"))
    }

    @Test func highlightsWithoutChapter_ungrouped() throws {
        let h = F.makeHighlight(href: nil, text: "Orphan highlight")

        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [],
            bookTitle: "No Chapter", bookAuthor: nil,
            chapterMap: F.chapterMap
        )
        let md = try formatMarkdown(payload)
        #expect(md.contains("## Ungrouped"))
        #expect(md.contains("> Orphan highlight"))
    }

    // MARK: - Notes

    @Test func notesIncluded() throws {
        let h = F.makeHighlight(text: "Important text", note: "My personal note")
        let n = F.makeAnnotation(content: "Standalone note")

        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [n],
            bookTitle: "Notes Book", bookAuthor: nil
        )
        let md = try formatMarkdown(payload)
        #expect(md.contains("*Note: My personal note*"))
        #expect(md.contains("*Note: Standalone note*"))
    }

    @Test func markdownSyntaxInNotes_preserved() throws {
        let noteWithMd = "This has **bold** and _italic_ and `code` and [link](url)"
        let h = F.makeHighlight(text: "Some text", note: noteWithMd)

        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [],
            bookTitle: "MD Syntax", bookAuthor: nil
        )
        let md = try formatMarkdown(payload)
        #expect(md.contains(noteWithMd))
    }

    // MARK: - Bookmarks

    @Test func bookmarksIncluded() throws {
        let b = F.makeBookmark(title: "Important Page")
        let payload = AnnotationExporter.buildPayload(
            highlights: [], bookmarks: [b], notes: [],
            bookTitle: "Bookmarks Book", bookAuthor: nil
        )
        let md = try formatMarkdown(payload)
        #expect(md.contains("- Important Page"))
    }

    @Test func bookmarkWithoutTitle_usesDefault() throws {
        let b = F.makeBookmark(title: nil)
        let payload = AnnotationExporter.buildPayload(
            highlights: [], bookmarks: [b], notes: [],
            bookTitle: "Test", bookAuthor: nil
        )
        let md = try formatMarkdown(payload)
        #expect(md.contains("- Bookmark"))
    }

    // MARK: - Helpers

    private func formatMarkdown(_ payload: AnnotationExportPayload) throws -> String {
        let data = try MarkdownExportFormatter().format(payload)
        return String(data: data, encoding: .utf8)!
    }
}
