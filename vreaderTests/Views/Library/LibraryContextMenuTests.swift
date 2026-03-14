// Purpose: Tests for WI-006 comprehensive book context menu.
// Validates context menu actions, BookInfoSheet metadata display,
// file size formatting edge cases, file URL resolution, and share sheet behavior.
//
// @coordinates-with: LibraryView.swift, BookInfoSheet.swift, FileSizeFormatter.swift,
//   ShareSheet.swift, LibraryBookItem.swift

import Testing
import Foundation
@testable import vreader

// MARK: - FileSizeFormatter Tests

@Suite("FileSizeFormatter")
struct FileSizeFormatterTests {

    @Test func formatsBytes() {
        let result = FileSizeFormatter.format(byteCount: 500)
        #expect(result == "500 bytes")
    }

    @Test func formatsKilobytes() {
        let result = FileSizeFormatter.format(byteCount: 1024)
        #expect(result == "1 KB")
    }

    @Test func formatsKilobytesRounded() {
        let result = FileSizeFormatter.format(byteCount: 2560)
        // ByteCountFormatter uses decimal rounding
        #expect(result == "3 KB")
    }

    @Test func formatsMegabytes() {
        let result = FileSizeFormatter.format(byteCount: 2_516_582)
        #expect(result == "2.5 MB")
    }

    @Test func formatsGigabytes() {
        let result = FileSizeFormatter.format(byteCount: 1_073_741_824)
        #expect(result == "1.07 GB")
    }

    @Test func formatsZeroBytes() {
        let result = FileSizeFormatter.format(byteCount: 0)
        #expect(result == "Zero KB")
    }

    @Test func formatsNegativeAsZero() {
        let result = FileSizeFormatter.format(byteCount: -100)
        #expect(result == "Zero KB")
    }

    @Test func formatsExactMegabyte() {
        let result = FileSizeFormatter.format(byteCount: 1_048_576)
        #expect(result == "1 MB")
    }
}

// MARK: - BookInfoSheet ViewModel Tests

@Suite("BookInfoSheet")
struct BookInfoSheetTests {

    @Test func displaysTitle() {
        let book = LibraryBookItem.stub(title: "Test Book Title")
        let vm = BookInfoViewModel(book: book)
        #expect(vm.title == "Test Book Title")
    }

    @Test func displaysAuthorWhenPresent() {
        let book = LibraryBookItem.stub(author: "Jane Austen")
        let vm = BookInfoViewModel(book: book)
        #expect(vm.author == "Jane Austen")
    }

    @Test func displaysUnknownAuthorWhenNil() {
        let book = LibraryBookItem.stub(author: nil)
        let vm = BookInfoViewModel(book: book)
        #expect(vm.author == "Unknown Author")
    }

    @Test func displaysFormatUppercased() {
        let book = LibraryBookItem.stub(format: "epub")
        let vm = BookInfoViewModel(book: book)
        #expect(vm.formatDisplay == "EPUB")
    }

    @Test func displaysMarkdownFormat() {
        let book = LibraryBookItem.stub(format: "md")
        let vm = BookInfoViewModel(book: book)
        #expect(vm.formatDisplay == "Markdown")
    }

    @Test func displaysTXTFormat() {
        let book = LibraryBookItem.stub(format: "txt")
        let vm = BookInfoViewModel(book: book)
        #expect(vm.formatDisplay == "TXT")
    }

    @Test func displaysPDFFormat() {
        let book = LibraryBookItem.stub(format: "pdf")
        let vm = BookInfoViewModel(book: book)
        #expect(vm.formatDisplay == "PDF")
    }

    @Test func displaysFileSizeFromByteCount() {
        let book = LibraryBookItem.stub(format: "epub", fileByteCount: 2_516_582)
        let vm = BookInfoViewModel(book: book)
        #expect(vm.fileSize == "2.5 MB")
    }

    @Test func displaysUnknownFileSizeWhenZero() {
        let book = LibraryBookItem.stub(format: "epub", fileByteCount: 0)
        let vm = BookInfoViewModel(book: book)
        #expect(vm.fileSize == "Unknown")
    }

    @Test func displaysDateAdded() {
        let date = Date(timeIntervalSince1970: 1_700_000_000) // Nov 14, 2023
        let book = LibraryBookItem.stub(addedAt: date)
        let vm = BookInfoViewModel(book: book)
        // Should produce a non-empty formatted date
        #expect(!vm.dateAdded.isEmpty)
    }

    @Test func displaysLastReadWhenPresent() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let book = LibraryBookItem.stub(lastReadAt: date)
        let vm = BookInfoViewModel(book: book)
        #expect(vm.lastRead != nil)
        #expect(!vm.lastRead!.isEmpty)
    }

    @Test func lastReadIsNilWhenNeverRead() {
        let book = LibraryBookItem.stub(lastReadAt: nil)
        let vm = BookInfoViewModel(book: book)
        #expect(vm.lastRead == nil)
    }

    @Test func displaysReadingTimeWhenNonZero() {
        let book = LibraryBookItem.stub(totalReadingSeconds: 3600)
        let vm = BookInfoViewModel(book: book)
        #expect(vm.readingTime != nil)
    }

    @Test func readingTimeNilWhenZero() {
        let book = LibraryBookItem.stub(totalReadingSeconds: 0)
        let vm = BookInfoViewModel(book: book)
        #expect(vm.readingTime == nil)
    }

    @Test func handlesVeryLongTitle() {
        let longTitle = String(repeating: "A", count: 300)
        let book = LibraryBookItem.stub(title: longTitle)
        let vm = BookInfoViewModel(book: book)
        // Title should pass through (truncation is SwiftUI's job)
        #expect(vm.title == longTitle)
    }

    @Test func handlesUnknownFormat() {
        let book = LibraryBookItem.stub(format: "xyz")
        let vm = BookInfoViewModel(book: book)
        #expect(vm.formatDisplay == "XYZ")
    }
}

// MARK: - LibraryBookItem.resolvedFileURL Tests

@Suite("LibraryBookItem.resolvedFileURL")
struct ResolvedFileURLTests {

    @Test func resolvesEpubURL() {
        let book = LibraryBookItem.stub(
            fingerprintKey: "epub:abc123:1024",
            format: "epub"
        )
        let url = book.resolvedFileURL
        #expect(url.lastPathComponent == "epub_abc123_1024.epub")
        #expect(url.pathComponents.contains("ImportedBooks"))
    }

    @Test func resolvesPdfURL() {
        let book = LibraryBookItem.stub(
            fingerprintKey: "pdf:def456:2048",
            format: "pdf"
        )
        let url = book.resolvedFileURL
        #expect(url.lastPathComponent == "pdf_def456_2048.pdf")
    }

    @Test func resolvesTxtURL() {
        let book = LibraryBookItem.stub(
            fingerprintKey: "txt:ghi789:512",
            format: "txt"
        )
        let url = book.resolvedFileURL
        #expect(url.lastPathComponent == "txt_ghi789_512.txt")
    }

    @Test func resolvesMdURL() {
        let book = LibraryBookItem.stub(
            fingerprintKey: "md:jkl012:256",
            format: "md"
        )
        let url = book.resolvedFileURL
        #expect(url.lastPathComponent == "md_jkl012_256.md")
    }

    @Test func replacesColonsInFingerprintKey() {
        let book = LibraryBookItem.stub(
            fingerprintKey: "epub:a1b2c3:9999",
            format: "epub"
        )
        let url = book.resolvedFileURL
        // Colons replaced with underscores in the filename
        #expect(!url.lastPathComponent.contains(":"))
        #expect(url.lastPathComponent == "epub_a1b2c3_9999.epub")
    }

    @Test func unknownFormatFallsBackToRawExtension() {
        let book = LibraryBookItem.stub(
            fingerprintKey: "xyz:abc:100",
            format: "xyz"
        )
        let url = book.resolvedFileURL
        #expect(url.pathExtension == "xyz")
    }

    @Test func urlIsFileURL() {
        let book = LibraryBookItem.stub()
        let url = book.resolvedFileURL
        #expect(url.isFileURL)
    }

    @Test func urlIsInApplicationSupportDirectory() {
        let book = LibraryBookItem.stub()
        let url = book.resolvedFileURL
        let appSupportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #expect(url.path.hasPrefix(appSupportDir.path))
    }
}

// MARK: - ShareSheet Share Items Tests

@Suite("ShareSheet.shareItems")
struct ShareSheetItemsTests {

    @Test func shareItemsContainsFileURL() {
        let book = LibraryBookItem.stub(
            fingerprintKey: "epub:abc123:1024",
            format: "epub"
        )
        let items = ShareSheet.activityItems(for: book)
        let urls = items.compactMap { $0 as? URL }
        #expect(urls.count == 1)
        #expect(urls.first?.lastPathComponent == "epub_abc123_1024.epub")
    }

    @Test func shareItemsUsesResolvedFileURL() {
        let book = LibraryBookItem.stub(
            fingerprintKey: "pdf:def456:2048",
            format: "pdf"
        )
        let items = ShareSheet.activityItems(for: book)
        let urls = items.compactMap { $0 as? URL }
        #expect(urls.first == book.resolvedFileURL)
    }

    @Test func shareItemsContainsExactlyOneItem() {
        let book = LibraryBookItem.stub()
        let items = ShareSheet.activityItems(for: book)
        #expect(items.count == 1)
    }
}
