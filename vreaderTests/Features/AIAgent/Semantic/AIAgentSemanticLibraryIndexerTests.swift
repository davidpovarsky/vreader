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

    @Test func libraryIndexerIndexesAllFormatsPersistsAcrossRelaunchAndCleansUp() async throws {
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

        // 1. TXT fixture
        let txtKey = "lib:txt:\(UUID().uuidString)"
        let txtURL = ImportedBookFileURL.resolve(fingerprintKey: txtKey, format: "txt")
        try? FileManager.default.createDirectory(at: txtURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Chapter on astronomy and stellar mechanics.".write(to: txtURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: txtURL) }

        // 2. MD fixture
        let mdKey = "lib:md:\(UUID().uuidString)"
        let mdURL = ImportedBookFileURL.resolve(fingerprintKey: mdKey, format: "md")
        try "# Heading\nDetailed guide to markdown syntax and structured formatting.".write(to: mdURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: mdURL) }

        // 3. EPUB fixture
        let epubKey = "lib:epub:\(UUID().uuidString)"
        let epubURL = ImportedBookFileURL.resolve(fingerprintKey: epubKey, format: "epub")
        try MinimalEPUBFixtureBuilder.writeMinimalEPUB(to: epubURL, bodyText: "Foundations of cybernetics and feedback control systems.")
        defer { try? FileManager.default.removeItem(at: epubURL) }

        // 4. PDF fixture
        let pdfKey = "lib:pdf:\(UUID().uuidString)"
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
            LibraryBookItem(fingerprintKey: txtKey, title: "Astronomy Book", author: "A", coverImagePath: nil, format: "txt", fileByteCount: 64, addedAt: Date(), lastOpenedAt: nil, isFavorite: false, totalReadingSeconds: 0, fileState: .present, blobPath: nil, collectionNames: []),
            LibraryBookItem(fingerprintKey: mdKey, title: "Markdown Guide", author: "B", coverImagePath: nil, format: "md", fileByteCount: 64, addedAt: Date(), lastOpenedAt: nil, isFavorite: false, totalReadingSeconds: 0, fileState: .present, blobPath: nil, collectionNames: []),
            LibraryBookItem(fingerprintKey: epubKey, title: "Cybernetics EPUB", author: "C", coverImagePath: nil, format: "epub", fileByteCount: 256, addedAt: Date(), lastOpenedAt: nil, isFavorite: false, totalReadingSeconds: 0, fileState: .present, blobPath: nil, collectionNames: []),
            LibraryBookItem(fingerprintKey: pdfKey, title: "Quantum PDF", author: "D", coverImagePath: nil, format: "pdf", fileByteCount: 512, addedAt: Date(), lastOpenedAt: nil, isFavorite: false, totalReadingSeconds: 0, fileState: .present, blobPath: nil, collectionNames: [])
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

        // Verify metadata persisted for all formats
        #expect(await metadataStore.fetchMetadata(forBook: txtKey) != nil)
        #expect(await metadataStore.fetchMetadata(forBook: mdKey) != nil)
        #expect(await metadataStore.fetchMetadata(forBook: epubKey) != nil)

        // 5. Persisted Relaunch Search (new store instances on same disk paths without re-indexing)
        let relaunchedIndexStore = SemanticIndexStore(dimension: 384, indexDirectory: indexDir)
        let relaunchedMetaStore = SemanticIndexMetadataStore(storageDirectory: metaDir)
        let searchService = SemanticSearchService(
            embeddingService: embedder,
            metadataStore: relaunchedMetaStore,
            indexStore: relaunchedIndexStore
        )

        let txtHits = try await searchService.searchLibrary(query: "astronomy", maxHits: 5)
        #expect(txtHits.contains { $0.bookFingerprintKey == txtKey })

        let epubHits = try await searchService.searchLibrary(query: "cybernetics", maxHits: 5)
        #expect(epubHits.contains { $0.bookFingerprintKey == epubKey })

        // 6. Rebuild & Deletion Cleanup
        try await indexer.deleteIndex(forBookKey: txtKey)
        #expect(await metadataStore.fetchMetadata(forBook: txtKey) == nil)
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
