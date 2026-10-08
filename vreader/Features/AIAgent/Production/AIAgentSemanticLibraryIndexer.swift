// Purpose: Background semantic library indexer for Feature #177.
// Enumerates on-device books through LibraryPersisting, extracts format-authoritative chunks
// (EPUB, PDF with OCR fallback, TXT/MD), embeds via MLX E5, and populates the shared USearch index.

import Foundation
import OSLog
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum AIAgentSemanticLibraryIndexerState: Sendable, Equatable {
    case idle
    case indexing(current: Int, total: Int, currentBookTitle: String)
    case completed(totalIndexed: Int)
    case cancelled
    case failed(String)

    var isIndexing: Bool {
        if case .indexing = self { return true }
        return false
    }

    var displayDescription: String {
        switch self {
        case .idle:
            return "Idle"
        case .indexing(let current, let total, let title):
            return "Indexing \(current) of \(total): \(title)"
        case .completed(let total):
            return "Indexed \(total) books"
        case .cancelled:
            return "Indexing cancelled"
        case .failed(let error):
            return "Indexing failed: \(error)"
        }
    }
}

actor AIAgentSemanticLibraryIndexer {
    private static let log = Logger(subsystem: "com.vreader.app", category: "AIAgentSemanticLibraryIndexer")

    private let library: any LibraryPersisting
    private let coordinator: SemanticIndexCoordinator
    private let metadataStore: SemanticIndexMetadataStore
    private let indexStore: SemanticIndexStore
    private let embeddingService: any SemanticEmbeddingProviding
    private let ocrService: (any PDFOCRServicing)?

    private var activeTask: Task<Void, Error>?
    private(set) var state: AIAgentSemanticLibraryIndexerState = .idle

    init(
        library: any LibraryPersisting,
        coordinator: SemanticIndexCoordinator,
        metadataStore: SemanticIndexMetadataStore = SemanticIndexMetadataStore(),
        indexStore: SemanticIndexStore = SemanticIndexStore(),
        embeddingService: (any SemanticEmbeddingProviding)? = nil,
        ocrService: (any PDFOCRServicing)? = nil
    ) {
        self.library = library
        self.coordinator = coordinator
        self.metadataStore = metadataStore
        self.indexStore = indexStore
        self.embeddingService = embeddingService ?? MLXE5EmbeddingService()
        self.ocrService = ocrService
    }

    /// Triggers background indexing of all eligible library books.
    func startIndexing(forceRebuild: Bool = false) {
        guard activeTask == nil else {
            Self.log.info("Library indexing is already in flight; ignoring new request.")
            return
        }

        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performLibraryIndexing(forceRebuild: forceRebuild)
                await self.updateState(.completed(totalIndexed: await self.countIndexedBooks()))
            } catch is CancellationError {
                await self.updateState(.cancelled)
                Self.log.info("Library indexing cancelled.")
            } catch {
                await self.updateState(.failed(error.localizedDescription))
                Self.log.error("Library indexing failed: \(error.localizedDescription)")
            }
            await self.clearActiveTask()
        }
    }

    func cancelIndexing() {
        if let task = activeTask {
            task.cancel()
            activeTask = nil
            state = .cancelled
        }
        Task { [coordinator] in
            await coordinator.rebuildAll()
        }
    }

    func rebuildLibraryIndex() async throws {
        cancelIndexing()
        try await coordinator.rebuildAll()
        startIndexing(forceRebuild: true)
    }

    func deleteIndex(forBookKey bookKey: String) async throws {
        try await coordinator.removeBookIndex(fingerprintKey: bookKey)
    }

    private func performLibraryIndexing(forceRebuild: Bool) async throws {
        let allBooks = try await library.fetchAllLibraryBooks()
        let eligible = allBooks.filter { book in
            let fmt = book.format.lowercased()
            let isSupportedFormat = (fmt == "epub" || fmt == "pdf" || fmt == "txt" || fmt == "md")
            let isOnDevice = (book.fileState != .remoteOnly && book.fileState != .downloading)
            return isSupportedFormat && isOnDevice
        }

        let total = eligible.count
        Self.log.info("Starting library indexing for \(total) eligible books (forceRebuild: \(forceRebuild))")

        var processedCount = 0
        for (index, book) in eligible.enumerated() {
            try Task.checkCancellation()

            state = .indexing(current: index + 1, total: total, currentBookTitle: book.title)

            // Check if existing index is compatible
            if !forceRebuild,
               let existing = await metadataStore.fetchMetadata(forBook: book.fingerprintKey),
               existing.isCompatible(withActiveModel: AISemanticModelManager.modelIdentifier, dimension: embeddingService.dimension) {
                processedCount += 1
                continue
            }

            guard let fileURL = ImportedBookFileURL.resolveExisting(fingerprintKey: book.fingerprintKey, format: book.format) else {
                Self.log.warning("Could not resolve local file for book \(book.fingerprintKey)")
                continue
            }

            do {
                let chunks = try await extractChunks(for: book, fileURL: fileURL)
                if !chunks.isEmpty {
                    try await coordinator.indexBook(fingerprintKey: book.fingerprintKey, chunks: chunks)
                    processedCount += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.log.error("Failed to index book \(book.title) (\(book.fingerprintKey)): \(error.localizedDescription)")
                // Do not crash the entire batch on a single unreadable book; continue indexing
            }
        }
    }

    // MARK: - Format Extraction

    private func extractChunks(for book: LibraryBookItem, fileURL: URL) async throws -> [AIDocumentChunk] {
        switch book.format.lowercased() {
        case "epub":
            return try await extractEPUBChunks(for: book, fileURL: fileURL)
        case "pdf":
            return try await extractPDFChunks(for: book, fileURL: fileURL)
        case "txt", "md":
            return try extractPlainTextChunks(for: book, fileURL: fileURL)
        default:
            return []
        }
    }

    private func extractEPUBChunks(for book: LibraryBookItem, fileURL: URL) async throws -> [AIDocumentChunk] {
        let parser = EPUBParser()
        do {
            let metadata = try await parser.open(url: fileURL)
            var chunks: [AIDocumentChunk] = []

            for (idx, item) in metadata.spineItems.enumerated() {
                try Task.checkCancellation()
                guard let xhtml = try? await parser.contentForSpineItem(href: item.href) else { continue }
                let plain = EPUBTextExtractor.stripHTML(xhtml).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !plain.isEmpty else { continue }

                let chunk = AIDocumentChunk(
                    id: "\(book.fingerprintKey):\(item.href)",
                    bookFingerprintKey: book.fingerprintKey,
                    sourceUnitID: item.href,
                    sourceUnitIndex: idx,
                    text: plain,
                    locator: Locator(
                        bookFingerprint: DocumentFingerprint(scheme: "library", value: book.fingerprintKey),
                        href: item.href
                    ),
                    sourceLabel: item.title ?? "Section \(idx + 1)",
                    chapterTitle: item.title,
                    pageIndex: nil,
                    href: item.href,
                    localStartUTF16: 0,
                    localEndUTF16: plain.utf16.count,
                    globalStartUTF16: nil,
                    globalEndUTF16: nil,
                    isOCRDerived: false
                )
                chunks.append(chunk)
            }
            await parser.close()
            return chunks
        } catch {
            await parser.close()
            throw error
        }
    }

    private func extractPDFChunks(for book: LibraryBookItem, fileURL: URL) async throws -> [AIDocumentChunk] {
        #if canImport(PDFKit)
        guard let doc = PDFKit.PDFDocument(url: fileURL) else {
            throw NSError(domain: "vreader.semantic.indexer", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Failed to open PDF document: \(fileURL.lastPathComponent)"
            ])
        }
        guard !doc.isLocked else {
            Self.log.info("Skipping locked PDF book: \(book.fingerprintKey)")
            return []
        }

        var chunks: [AIDocumentChunk] = []
        for pageIndex in 0..<doc.pageCount {
            try Task.checkCancellation()
            guard let page = doc.page(at: pageIndex) else { continue }

            var pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var isOCR = false

            #if canImport(UIKit)
            if pageText.count < 30, let ocrService {
                let pageBounds = page.bounds(for: .mediaBox)
                let maxDimension = max(pageBounds.width, pageBounds.height, 1)
                let scale = min(1.5, 1200.0 / maxDimension)
                let targetSize = CGSize(width: max(1, pageBounds.width * scale), height: max(1, pageBounds.height * scale))
                let renderer = UIGraphicsImageRenderer(size: targetSize)
                let image = renderer.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: targetSize))
                    ctx.cgContext.translateBy(x: 0, y: targetSize.height)
                    ctx.cgContext.scaleBy(x: scale, y: -scale)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
                if let ocrResult = try? await ocrService.recognizeText(in: image) {
                    let recognized = ocrResult.lines.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !recognized.isEmpty {
                        pageText = recognized
                        isOCR = true
                    }
                }
            }
            #endif

            guard !pageText.isEmpty else { continue }

            let chunk = AIDocumentChunk(
                id: "\(book.fingerprintKey):p\(pageIndex + 1)",
                bookFingerprintKey: book.fingerprintKey,
                sourceUnitID: "page_\(pageIndex + 1)",
                sourceUnitIndex: pageIndex,
                text: pageText,
                locator: Locator(
                    bookFingerprint: DocumentFingerprint(scheme: "library", value: book.fingerprintKey),
                    page: pageIndex + 1
                ),
                sourceLabel: "Page \(pageIndex + 1)",
                chapterTitle: nil,
                pageIndex: pageIndex + 1,
                href: nil,
                localStartUTF16: 0,
                localEndUTF16: pageText.utf16.count,
                globalStartUTF16: nil,
                globalEndUTF16: nil,
                isOCRDerived: isOCR
            )
            chunks.append(chunk)
        }
        return chunks
        #else
        return []
        #endif
    }

    private func extractPlainTextChunks(for book: LibraryBookItem, fileURL: URL) throws -> [AIDocumentChunk] {
        let plain = try ClosedBookTextExtractor.extractPlainText(url: fileURL)
        let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let chunk = AIDocumentChunk(
            id: "\(book.fingerprintKey):content",
            bookFingerprintKey: book.fingerprintKey,
            sourceUnitID: "content",
            sourceUnitIndex: 0,
            text: trimmed,
            locator: Locator(
                bookFingerprint: DocumentFingerprint(scheme: "library", value: book.fingerprintKey),
                href: fileURL.lastPathComponent
            ),
            sourceLabel: book.title,
            chapterTitle: nil,
            pageIndex: nil,
            href: fileURL.lastPathComponent,
            localStartUTF16: 0,
            localEndUTF16: trimmed.utf16.count,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )
        return [chunk]
    }

    private func updateState(_ newState: AIAgentSemanticLibraryIndexerState) {
        self.state = newState
    }

    private func clearActiveTask() {
        self.activeTask = nil
    }

    private func countIndexedBooks() async -> Int {
        let all = (try? await library.fetchAllLibraryBooks()) ?? []
        var count = 0
        for b in all {
            if (await metadataStore.fetchMetadata(forBook: b.fingerprintKey)) != nil {
                count += 1
            }
        }
        return count
    }
}
