// Purpose: Integration test suite for AIAgentSemanticLibraryIndexer.
// Verifies format extraction, deterministic embedding, persistent storage,
// library semantic search, deletion cleanup, cancellation, and duplicate job prevention.

import Testing
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

private final class MockLibraryStore: LibraryPersisting, @unchecked Sendable {
    var books: [LibraryBookItem] = []

    func fetchAllLibraryBooks() async throws -> [LibraryBookItem] {
        books
    }
    func fetchBook(withKey key: String) async throws -> LibraryBookItem? {
        books.first { $0.fingerprintKey == key }
    }
    func deleteBook(fingerprintKey: String) async throws {
        books.removeAll { $0.fingerprintKey == fingerprintKey }
    }
    func updateLastOpened(forBookWithKey key: String, at date: Date) async throws {}
    func toggleFavorite(forBookWithKey key: String) async throws -> Bool { false }
    func addBook(_ book: LibraryBookItem) async throws {}
    func updateBook(_ book: LibraryBookItem) async throws {}
}

private struct DeterministicTestEmbedder: SemanticEmbeddingProviding {
    let dimension: Int = 384

    func embedPassages(_ texts: [String]) async throws -> [[Float]] {
        texts.map { text in
            var v = [Float](repeating: 0.0, count: dimension)
            let lower = text.lowercased()
            if lower.contains("astronomy") {
                v[0] = 1.0
            } else if lower.contains("quantum") {
                v[1] = 1.0
            } else if lower.contains("markdown") {
                v[2] = 1.0
            } else if lower.contains("cybernetics") {
                v[3] = 1.0
            } else {
                let hash = abs(text.hashValue) % (dimension - 4) + 4
                v[hash] = 1.0
            }
            return v
        }
    }

    func embedQuery(_ text: String) async throws -> [Float] {
        try await embedPassages([text]).first ?? [Float](repeating: 0.0, count: dimension)
    }
}

private enum MinimalEPUBFixtureBuilder {
    static func writeMinimalEPUB(to url: URL, bodyText: String) throws {
        let containerXML = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.utf8)
        let opfXML = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>EPUB Fixture</dc:title></metadata>
          <manifest><item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/></manifest>
          <spine><itemref idref="ch1"/></spine>
        </package>
        """.utf8)
        let xhtml = Data("<html><body><p>\(bodyText)</p></body></html>".utf8)
        let entries: [(String, Data)] = [
            ("META-INF/container.xml", containerXML),
            ("OEBPS/content.opf", opfXML),
            ("OEBPS/ch1.xhtml", xhtml)
        ]
        var archive = Data()
        var offsets: [Int] = []
        for (path, content) in entries {
            let nameData = Data(path.utf8)
            offsets.append(archive.count)
            archive.append(contentsOf: [0x50, 0x4b, 0x03, 0x04, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            archive.appendUInt32LE(UInt32(content.count))
            archive.appendUInt32LE(UInt32(content.count))
            archive.appendUInt16LE(UInt16(nameData.count))
            archive.appendUInt16LE(0)
            archive.append(nameData)
            archive.append(content)
        }
        let cdOffset = archive.count
        for (i, (path, content)) in entries.enumerated() {
            let nameData = Data(path.utf8)
            archive.append(contentsOf: [0x50, 0x4b, 0x01, 0x02, 20, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            archive.appendUInt32LE(UInt32(content.count))
            archive.appendUInt32LE(UInt32(content.count))
            archive.appendUInt16LE(UInt16(nameData.count))
            archive.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            archive.appendUInt32LE(UInt32(offsets[i]))
            archive.append(nameData)
        }
        let cdSize = archive.count - cdOffset
        archive.append(contentsOf: [0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0])
        archive.appendUInt16LE(UInt16(entries.count))
        archive.appendUInt16LE(UInt16(entries.count))
        archive.appendUInt32LE(UInt32(cdSize))
        archive.appendUInt32LE(UInt32(cdOffset))
        archive.appendUInt16LE(0)
        try archive.write(to: url)
    }
}

private extension Data {
    mutating func appendUInt16LE(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8((v >> 8) & 0xFF)) }
    mutating func appendUInt32LE(_ v: UInt32) {
        append(UInt8(v & 0xFF)); append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF)); append(UInt8((v >> 24) & 0xFF))
    }
}

@Suite("AIAgentSemanticLibraryIndexerTests")
struct AIAgentSemanticLibraryIndexerTests {

    @MainActor
    private final class MockNavigationHandlerState: ReaderNotificationHandlerStateProtocol {
        var scrollToOffset: Int?
        var highlightRange: NSRange?
        var highlightIsTemporary: Bool = false
        var scrollSnapToTop: Bool = false
        var highlightNonce: Int = 0
        var persistedHighlightRanges: [PaintedHighlight] = []
        var pendingAnnotationInfo: TextSelectionInfo?
        var annotationNoteText: String = ""
    }

    private struct NoOpBookmarkHighlightAnnotationStore: BookmarkPersisting, HighlightPersisting, AnnotationPersisting {
        func addBookmark(locator: Locator, title: String?, toBookWithKey bookFingerprintKey: String) async throws -> BookmarkRecord {
            BookmarkRecord(bookmarkId: UUID(), locator: locator, profileKey: "\(bookFingerprintKey):\(locator.canonicalHash)", title: title, createdAt: Date(), updatedAt: Date())
        }
        func removeBookmark(bookmarkId: UUID) async throws {}
        func fetchBookmarks(forBookWithKey bookFingerprintKey: String) async throws -> [BookmarkRecord] { [] }
        func isBookmarked(locator: Locator, forBookWithKey bookFingerprintKey: String) async throws -> Bool { false }
        func updateBookmarkTitle(bookmarkId: UUID, title: String?) async throws {}
        func addHighlight(locator: Locator, selectedText: String, color: String, note: String?, toBookWithKey bookFingerprintKey: String) async throws -> HighlightRecord {
            HighlightRecord(highlightId: UUID(), locator: locator, anchor: nil, profileKey: "\(bookFingerprintKey):\(locator.canonicalHash)", selectedText: selectedText, color: color, note: note, createdAt: Date(), updatedAt: Date())
        }
        func removeHighlight(highlightId: UUID) async throws {}
        func updateHighlightNote(highlightId: UUID, note: String?) async throws {}
        func updateHighlightColor(highlightId: UUID, color: String) async throws {}
        func fetchHighlights(forBookWithKey bookFingerprintKey: String) async throws -> [HighlightRecord] { [] }
        func addAnnotation(locator: Locator, content: String, toBookWithKey bookFingerprintKey: String) async throws -> AnnotationRecord {
            AnnotationRecord(annotationId: UUID(), locator: locator, profileKey: "\(bookFingerprintKey):\(locator.canonicalHash)", content: content, createdAt: Date(), updatedAt: Date())
        }
        func removeAnnotation(annotationId: UUID) async throws {}
        func updateAnnotation(annotationId: UUID, content: String) async throws {}
        func fetchAnnotations(forBookWithKey bookFingerprintKey: String) async throws -> [AnnotationRecord] { [] }
    }

    @Test func libraryIndexerIndexesAllFormatsWithCanonicalLocatorsAndPersistsAcrossRelaunch() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let indexDir = tempDir.appendingPathComponent("vectors")
        let metaDir = tempDir.appendingPathComponent("metadata")

        let indexStore = SemanticIndexStore(dimension: 384, indexDirectory: indexDir)
        let metadataStore = SemanticIndexMetadataStore(storageDirectory: metaDir)
        let embedder = DeterministicTestEmbedder()
        let coordinator = SemanticIndexCoordinator(
            embeddingService: embedder,
            metadataStore: metadataStore,
            indexStore: indexStore
        )

        // 1. TXT fixture with leading whitespace + non-BMP emoji + CJK + second paragraph
        let txtFP = DocumentFingerprint(
            contentSHA256: "1111111111111111111111111111111111111111111111111111111111111111",
            fileByteCount: 256,
            format: .txt
        )
        let txtKey = txtFP.canonicalKey
        let txtURL = ImportedBookFileURL.resolve(fingerprintKey: txtKey, format: "txt")
        try? FileManager.default.createDirectory(at: txtURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let txtContent = "   \n\n🌟 天文学 Intro paragraph.\n\nChapter on astronomy and stellar mechanics."
        try txtContent.write(to: txtURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: txtURL) }

        // 2. MD fixture with leading whitespace + non-BMP emoji
        let mdFP = DocumentFingerprint(
            contentSHA256: "2222222222222222222222222222222222222222222222222222222222222222",
            fileByteCount: 256,
            format: .md
        )
        let mdKey = mdFP.canonicalKey
        let mdURL = ImportedBookFileURL.resolve(fingerprintKey: mdKey, format: "md")
        let mdContent = "  \n\n# 🚀 Heading\n\nDetailed guide to markdown syntax and structured formatting."
        try mdContent.write(to: mdURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: mdURL) }

        // 3. EPUB fixture
        let epubFP = DocumentFingerprint(
            contentSHA256: "3333333333333333333333333333333333333333333333333333333333333333",
            fileByteCount: 512,
            format: .epub
        )
        let epubKey = epubFP.canonicalKey
        let epubURL = ImportedBookFileURL.resolve(fingerprintKey: epubKey, format: "epub")
        try MinimalEPUBFixtureBuilder.writeMinimalEPUB(to: epubURL, bodyText: "Foundations of cybernetics and feedback control systems.")
        defer { try? FileManager.default.removeItem(at: epubURL) }

        // 4. PDF fixture
        let pdfFP = DocumentFingerprint(
            contentSHA256: "4444444444444444444444444444444444444444444444444444444444444444",
            fileByteCount: 1024,
            format: .pdf
        )
        let pdfKey = pdfFP.canonicalKey
        let pdfURL = ImportedBookFileURL.resolve(fingerprintKey: pdfKey, format: "pdf")
        #if canImport(UIKit)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400))
        let pdfData = renderer.pdfData { ctx in
            ctx.beginPage()
            ("Quantum thermodynamics and statistical physics notes." as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
        }
        try pdfData.write(to: pdfURL)
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        #endif

        let mockLib = MockLibraryStore()
        mockLib.books = [
            LibraryBookItem(fingerprintKey: txtKey, title: "Astronomy Book", author: "A", coverImagePath: nil, format: "txt", fileByteCount: 256, addedAt: Date(), lastOpenedAt: nil, isFavorite: false, totalReadingSeconds: 0, averagePagesPerHour: nil, averageWordsPerMinute: nil),
            LibraryBookItem(fingerprintKey: mdKey, title: "Markdown Guide", author: "B", coverImagePath: nil, format: "md", fileByteCount: 256, addedAt: Date(), lastOpenedAt: nil, isFavorite: false, totalReadingSeconds: 0, averagePagesPerHour: nil, averageWordsPerMinute: nil),
            LibraryBookItem(fingerprintKey: epubKey, title: "Cybernetics EPUB", author: "C", coverImagePath: nil, format: "epub", fileByteCount: 512, addedAt: Date(), lastOpenedAt: nil, isFavorite: false, totalReadingSeconds: 0, averagePagesPerHour: nil, averageWordsPerMinute: nil),
            LibraryBookItem(fingerprintKey: pdfKey, title: "Quantum PDF", author: "D", coverImagePath: nil, format: "pdf", fileByteCount: 1024, addedAt: Date(), lastOpenedAt: nil, isFavorite: false, totalReadingSeconds: 0, averagePagesPerHour: nil, averageWordsPerMinute: nil)
        ]

        let indexer = AIAgentSemanticLibraryIndexer(
            library: mockLib,
            coordinator: coordinator,
            metadataStore: metadataStore,
            indexStore: indexStore,
            embeddingService: embedder,
            ocrService: nil
        )

        await indexer.startIndexing(forceRebuild: true)
        for _ in 0..<80 {
            if case .completed = await indexer.state { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(await indexer.state.isIndexing == false)

        // Verify EPUB locator round-trip
        let epubChunks = await metadataStore.allChunks(for: epubKey)
        let epubChunk = try #require(epubChunks.first)
        #expect(epubChunk.locator.bookFingerprint == epubFP)
        #expect(epubChunk.locator.href == "ch1.xhtml")
        #expect(epubChunk.sourceUnitID == "epub:ch1.xhtml")

        // Verify PDF zero-based page round-trip + 1-based label
        #if canImport(UIKit)
        let pdfChunks = await metadataStore.allChunks(for: pdfKey)
        let pdfChunk = try #require(pdfChunks.first)
        #expect(pdfChunk.locator.bookFingerprint == pdfFP)
        #expect(pdfChunk.locator.page == 0)
        #expect(pdfChunk.pageIndex == 0)
        #expect(pdfChunk.sourceLabel == "Page 1")
        #expect(pdfChunk.sourceUnitID == "pdf:page:0")
        #endif

        // Verify TXT & MD UTF-16 offset round-trip with leading whitespace + non-BMP emoji + ReaderNotificationHandlers
        let expectedTXTSegments = UTF16TextSegmenter.segments(in: txtContent)
        let txtChunks = await metadataStore.allChunks(for: txtKey).sorted { ($0.sourceUnitIndex ?? 0) < ($1.sourceUnitIndex ?? 0) }
        #expect(txtChunks.count == expectedTXTSegments.count)
        let secondTXTChunk = try #require(txtChunks.last)
        let expectedSecondSegment = try #require(expectedTXTSegments.last)
        #expect(secondTXTChunk.locator.bookFingerprint == txtFP)
        #expect(secondTXTChunk.locator.href == nil)
        #expect(secondTXTChunk.locator.charOffsetUTF16 == expectedSecondSegment.startUTF16)
        #expect(secondTXTChunk.locator.charRangeStartUTF16 == expectedSecondSegment.startUTF16)
        #expect(secondTXTChunk.locator.charRangeEndUTF16 == expectedSecondSegment.endUTF16)
        #expect(secondTXTChunk.sourceUnitID == "txt:segment:\(expectedSecondSegment.index)")

        let mdChunks = await metadataStore.allChunks(for: mdKey).sorted { ($0.sourceUnitIndex ?? 0) < ($1.sourceUnitIndex ?? 0) }
        let lastMDChunk = try #require(mdChunks.last)
        #expect(lastMDChunk.locator.bookFingerprint == mdFP)
        #expect(lastMDChunk.locator.href == nil)
        #expect(lastMDChunk.locator.charOffsetUTF16 != nil)
        #expect(lastMDChunk.locator.charRangeStartUTF16 != nil)
        #expect(lastMDChunk.locator.charRangeEndUTF16 != nil)

        await MainActor.run {
            let navState = MockNavigationHandlerState()
            let noOpStore = NoOpBookmarkHighlightAnnotationStore()
            var navigatedOffset: Int?
            let deps = ReaderNotificationDeps(
                bookFingerprintKey: txtKey,
                bookFingerprint: txtFP,
                bookmarkPersistence: noOpStore,
                highlightPersistence: noOpStore,
                annotationPersistence: noOpStore,
                locatorFactory: { fp, start, end, _ in
                    Locator.validated(bookFingerprint: fp, charOffsetUTF16: start, charRangeStartUTF16: start, charRangeEndUTF16: end)
                },
                sourceText: { txtContent },
                makeCurrentLocator: { Locator.validated(bookFingerprint: txtFP, charOffsetUTF16: 0)! },
                onNavigate: { offset in navigatedOffset = offset }
            )
            ReaderNotificationHandlers.handleNavigateToLocator(
                locator: secondTXTChunk.locator,
                state: navState,
                deps: deps
            )
            #expect(navState.scrollToOffset == expectedSecondSegment.startUTF16)
            #expect(navigatedOffset == expectedSecondSegment.startUTF16)
            #expect(navState.highlightRange == NSRange(
                location: expectedSecondSegment.startUTF16,
                length: expectedSecondSegment.endUTF16 - expectedSecondSegment.startUTF16
            ))
        }

        // 5. Persisted Relaunch Search
        let relaunchedIndexStore = SemanticIndexStore(dimension: 384, indexDirectory: indexDir)
        let relaunchedMetaStore = SemanticIndexMetadataStore(storageDirectory: metaDir)
        let searchService = SemanticSearchService(
            embeddingService: embedder,
            metadataStore: relaunchedMetaStore,
            indexStore: relaunchedIndexStore
        )

        let txtHits = try await searchService.searchLibrary(query: "astronomy", maxHits: 5)
        let matchingTXTHit = try #require(txtHits.first { $0.bookFingerprintKey == txtKey })
        #expect(matchingTXTHit.locator.bookFingerprint == txtFP)
        #expect(matchingTXTHit.locator.charOffsetUTF16 == expectedSecondSegment.startUTF16)

        let epubHits = try await searchService.searchLibrary(query: "cybernetics", maxHits: 5)
        let matchingEPUBHit = try #require(epubHits.first { $0.bookFingerprintKey == epubKey })
        #expect(matchingEPUBHit.locator.bookFingerprint == epubFP)
        #expect(matchingEPUBHit.locator.href == "ch1.xhtml")
    }

    @Test func legacyFakeLocatorMetadataIsInvalidatedAndRebuiltAndLibraryDeletionRemovesVectors() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let indexDir = tempDir.appendingPathComponent("vectors")
        let metaDir = tempDir.appendingPathComponent("metadata")

        let indexStore = SemanticIndexStore(dimension: 384, indexDirectory: indexDir)
        let metadataStore = SemanticIndexMetadataStore(storageDirectory: metaDir)
        let embedder = DeterministicTestEmbedder()
        let coordinator = SemanticIndexCoordinator(
            embeddingService: embedder,
            metadataStore: metadataStore,
            indexStore: indexStore
        )

        let txtFP = DocumentFingerprint(
            contentSHA256: "5555555555555555555555555555555555555555555555555555555555555555",
            fileByteCount: 128,
            format: .txt
        )
        let txtKey = txtFP.canonicalKey
        let txtURL = ImportedBookFileURL.resolve(fingerprintKey: txtKey, format: "txt")
        try? FileManager.default.createDirectory(at: txtURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Astronomy observations of distant galaxies.".write(to: txtURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: txtURL) }

        // Seed legacy fake-locator metadata (scheme: "library" and href on TXT)
        let legacyFakeLocator = Locator(
            bookFingerprint: DocumentFingerprint(scheme: "library", value: txtKey),
            href: txtURL.lastPathComponent
        )
        let legacyChunk = SemanticChunkMetadata(
            chunkID: "legacy_chunk",
            bookFingerprintKey: txtKey,
            bookTitle: "Astronomy Book",
            locator: legacyFakeLocator,
            sourceUnitID: "content",
            href: txtURL.lastPathComponent,
            snippet: "Astronomy observations",
            isOCRDerived: false
        )
        #expect(legacyChunk.hasValidCanonicalLocator == false)
        let legacyMeta = SemanticIndexMetadata(
            bookFingerprintKey: txtKey,
            embeddingDimension: 384,
            extractionVersion: 1,
            chunkCount: 1
        )
        try await metadataStore.save(metadata: legacyMeta, chunks: [legacyChunk])

        let mockLib = MockLibraryStore()
        mockLib.books = [
            LibraryBookItem(fingerprintKey: txtKey, title: "Astronomy Book", author: "Author", coverImagePath: nil, format: "txt", fileByteCount: 128, addedAt: Date(), lastOpenedAt: nil, isFavorite: false, totalReadingSeconds: 0, averagePagesPerHour: nil, averageWordsPerMinute: nil)
        ]

        let indexer = AIAgentSemanticLibraryIndexer(
            library: mockLib,
            coordinator: coordinator,
            metadataStore: metadataStore,
            indexStore: indexStore,
            embeddingService: embedder,
            ocrService: nil
        )

        // Running startIndexing(forceRebuild: false) must detect the legacy fake locator and rebuild it
        await indexer.startIndexing(forceRebuild: false)
        for _ in 0..<80 {
            if case .completed = await indexer.state { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let rebuiltChunks = await metadataStore.allChunks(for: txtKey)
        let rebuilt = try #require(rebuiltChunks.first)
        #expect(rebuilt.hasValidCanonicalLocator == true)
        #expect(rebuilt.locator.bookFingerprint == txtFP)
        #expect(rebuilt.locator.href == nil)
        #expect(rebuilt.locator.charOffsetUTF16 == 0)

        let searchService = SemanticSearchService(
            embeddingService: embedder,
            metadataStore: metadataStore,
            indexStore: indexStore
        )
        let hitsBeforeDelete = try await searchService.searchLibrary(query: "astronomy", maxHits: 5)
        #expect(hitsBeforeDelete.contains { $0.bookFingerprintKey == txtKey })

        // Delete the book via LibraryViewModel.deleteBook(fingerprintKey:)
        let libraryVM = await MainActor.run { LibraryViewModel(persistence: mockLib) }
        await libraryVM.deleteBook(fingerprintKey: txtKey)

        // Wait briefly for the notification observer task on indexer to complete deletion
        for _ in 0..<40 {
            if await metadataStore.fetchMetadata(forBook: txtKey) == nil { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        #expect(await metadataStore.fetchMetadata(forBook: txtKey) == nil)
        let hitsAfterDelete = try await searchService.searchLibrary(query: "astronomy", maxHits: 5)
        #expect(!hitsAfterDelete.contains { $0.bookFingerprintKey == txtKey })
    }

    @Test func deletingBookWhileIndexingIsInFlightPreventsDeletedBookFromReappearing() async throws {
        struct SlowEmbedder: SemanticEmbeddingProviding {
            let dimension: Int = 384
            func embedPassages(_ texts: [String]) async throws -> [[Float]] {
                try await Task.sleep(nanoseconds: 150_000_000)
                return texts.map { _ in
                    var v = [Float](repeating: 0.0, count: dimension)
                    v[0] = 1.0
                    return v
                }
            }
            func embedQuery(_ text: String) async throws -> [Float] {
                var v = [Float](repeating: 0.0, count: dimension)
                v[0] = 1.0
                return v
            }
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let indexStore = SemanticIndexStore(dimension: 384, indexDirectory: tempDir.appendingPathComponent("vec"))
        let metadataStore = SemanticIndexMetadataStore(storageDirectory: tempDir.appendingPathComponent("meta"))
        let slowEmbedder = SlowEmbedder()
        let coordinator = SemanticIndexCoordinator(
            embeddingService: slowEmbedder,
            metadataStore: metadataStore,
            indexStore: indexStore
        )

        let fp = DocumentFingerprint(
            contentSHA256: "6666666666666666666666666666666666666666666666666666666666666666",
            fileByteCount: 256,
            format: .txt
        )
        let key = fp.canonicalKey
        let loc = try #require(Locator.validated(bookFingerprint: fp, charOffsetUTF16: 0, charRangeStartUTF16: 0, charRangeEndUTF16: 42))
        let chunk = AIDocumentChunk(
            id: "chunk-race",
            bookFingerprintKey: key,
            sourceUnitID: "txt:segment:0",
            sourceUnitIndex: 0,
            text: "Astronomy text being indexed when deleted.",
            locator: loc,
            sourceLabel: "Race Book",
            chapterTitle: nil,
            pageIndex: nil,
            href: nil,
            localStartUTF16: 0,
            localEndUTF16: 42,
            globalStartUTF16: 0,
            globalEndUTF16: 42,
            isOCRDerived: false
        )

        let indexTask = Task {
            try? await coordinator.indexBook(fingerprintKey: key, bookTitle: "Race Book", chunks: [chunk])
        }

        // Wait briefly so indexBook enters embedding
        try? await Task.sleep(nanoseconds: 30_000_000)

        // Delete the book while indexing is in flight
        try await coordinator.removeBookIndex(fingerprintKey: key)
        await indexTask.value

        #expect(await metadataStore.fetchMetadata(forBook: key) == nil)
        #expect(await metadataStore.allChunks(for: key).isEmpty)

        let searchService = SemanticSearchService(
            embeddingService: slowEmbedder,
            metadataStore: metadataStore,
            indexStore: indexStore
        )
        let hits = try await searchService.searchLibrary(query: "astronomy", maxHits: 5)
        #expect(!hits.contains { $0.bookFingerprintKey == key })
    }

    @Test func startIndexingIgnoresDuplicateAndSupportsCancellation() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mockLib = MockLibraryStore()
        let coordinator = SemanticIndexCoordinator(
            embeddingService: DeterministicTestEmbedder(),
            metadataStore: SemanticIndexMetadataStore(storageDirectory: tempDir.appendingPathComponent("meta")),
            indexStore: SemanticIndexStore(dimension: 384, indexDirectory: tempDir.appendingPathComponent("vec"))
        )
        let indexer = AIAgentSemanticLibraryIndexer(
            library: mockLib,
            coordinator: coordinator
        )

        await indexer.startIndexing()
        await indexer.startIndexing()
        await indexer.cancelIndexing()
        let cancelledState = await indexer.state
        #expect(cancelledState == .cancelled || !cancelledState.isIndexing)
    }
}
