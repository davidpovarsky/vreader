// Purpose: Background semantic library indexer for Feature #177.
// Enumerates on-device books through LibraryPersisting, extracts format-authoritative chunks
// (EPUB, PDF with OCR fallback, TXT/MD), embeds via MLX E5, and populates the shared USearch index.

import Foundation
import OSLog
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(CoreGraphics)
import CoreGraphics
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

extension Notification.Name {
    static let libraryBookDidDelete = Notification.Name("vreader.library.bookDidDelete")
}

private final class DeletionObserverTokenBox: @unchecked Sendable {
    var token: NSObjectProtocol?
    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
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
    private let deletionObserverBox = DeletionObserverTokenBox()

    private var activeTask: Task<Void, Error>?
    private var deletedDuringRun: Set<String> = []
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

        let observerBox = self.deletionObserverBox
        observerBox.token = NotificationCenter.default.addObserver(
            forName: .libraryBookDidDelete,
            object: nil,
            queue: nil
        ) { [weak self] note in
            let key = (note.userInfo?["fingerprintKey"] as? String) ?? (note.object as? String)
            guard let key, !key.isEmpty else { return }
            Task { [weak self] in
                try? await self?.deleteIndex(forBookKey: key)
            }
        }
    }

    /// Triggers background indexing of all eligible library books.
    func startIndexing(forceRebuild: Bool = false) {
        guard activeTask == nil else {
            Self.log.info("Library indexing is already in flight; ignoring new request.")
            return
        }

        deletedDuringRun.removeAll()
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
    }

    func rebuildLibraryIndex() async throws {
        cancelIndexing()
        try await coordinator.rebuildAll()
        startIndexing(forceRebuild: true)
    }

    func deleteIndex(forBookKey bookKey: String) async throws {
        deletedDuringRun.insert(bookKey)
        try await coordinator.removeBookIndex(fingerprintKey: bookKey)
    }

    private func validatedFingerprint(for book: LibraryBookItem) -> DocumentFingerprint? {
        guard let fp = DocumentFingerprint(canonicalKey: book.fingerprintKey),
              fp.format.rawValue.lowercased() == book.format.lowercased() else {
            return nil
        }
        return fp
    }

    private func performLibraryIndexing(forceRebuild: Bool) async throws {
        let allBooks = try await library.fetchAllLibraryBooks()
        let currentLibraryKeys = Set(allBooks.map(\.fingerprintKey))
        for storedKey in await metadataStore.allBookKeys() where !currentLibraryKeys.contains(storedKey) {
            try? await coordinator.removeBookIndex(fingerprintKey: storedKey)
        }

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
            if deletedDuringRun.contains(book.fingerprintKey) {
                try? await coordinator.removeBookIndex(fingerprintKey: book.fingerprintKey)
                continue
            }

            state = .indexing(current: index + 1, total: total, currentBookTitle: book.title)

            guard let fingerprint = validatedFingerprint(for: book) else {
                Self.log.warning("Skipping book with invalid or mismatched canonical fingerprintKey: \(book.fingerprintKey) (format: \(book.format))")
                try? await coordinator.removeBookIndex(fingerprintKey: book.fingerprintKey)
                continue
            }

            // Check if existing index is compatible AND has valid canonical locators
            let existingMeta = await metadataStore.fetchMetadata(forBook: book.fingerprintKey)
            let existingChunks = await metadataStore.allChunks(for: book.fingerprintKey)
            let hasValidLocators = !existingChunks.isEmpty && existingChunks.allSatisfy(\.hasValidCanonicalLocator)

            if !forceRebuild,
               let existing = existingMeta,
               existing.isCompatible(withActiveModel: AISemanticModelManager.modelIdentifier, dimension: embeddingService.dimension),
               hasValidLocators {
                processedCount += 1
                continue
            }

            if existingMeta != nil || !existingChunks.isEmpty {
                try? await coordinator.removeBookIndex(fingerprintKey: book.fingerprintKey)
            }

            let fileURL = ImportedBookFileURL.resolveExisting(fingerprintKey: book.fingerprintKey, format: book.format)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                Self.log.warning("Could not resolve local file for book \(book.fingerprintKey)")
                continue
            }

            do {
                let chunks = try await extractChunks(for: book, fingerprint: fingerprint, fileURL: fileURL)
                if deletedDuringRun.contains(book.fingerprintKey) {
                    try? await coordinator.removeBookIndex(fingerprintKey: book.fingerprintKey)
                    continue
                }
                if !chunks.isEmpty {
                    try await coordinator.indexBook(
                        fingerprintKey: book.fingerprintKey,
                        bookTitle: book.title,
                        chunks: chunks
                    )
                    if deletedDuringRun.contains(book.fingerprintKey) {
                        try? await coordinator.removeBookIndex(fingerprintKey: book.fingerprintKey)
                    } else {
                        processedCount += 1
                    }
                }
            } catch is CancellationError {
                if deletedDuringRun.contains(book.fingerprintKey) {
                    try? await coordinator.removeBookIndex(fingerprintKey: book.fingerprintKey)
                    continue
                }
                throw CancellationError()
            } catch {
                Self.log.error("Failed to index book \(book.title) (\(book.fingerprintKey)): \(error.localizedDescription)")
                // Do not crash the entire batch on a single unreadable book; continue indexing
            }
        }
    }

    // MARK: - Format Extraction

    private func extractChunks(
        for book: LibraryBookItem,
        fingerprint: DocumentFingerprint,
        fileURL: URL
    ) async throws -> [AIDocumentChunk] {
        switch book.format.lowercased() {
        case "epub":
            return try await extractEPUBChunks(for: book, fingerprint: fingerprint, fileURL: fileURL)
        case "pdf":
            return try await extractPDFChunks(for: book, fingerprint: fingerprint, fileURL: fileURL)
        case "txt", "md":
            return try extractPlainTextChunks(for: book, fingerprint: fingerprint, fileURL: fileURL)
        default:
            return []
        }
    }

    private func extractEPUBChunks(
        for book: LibraryBookItem,
        fingerprint: DocumentFingerprint,
        fileURL: URL
    ) async throws -> [AIDocumentChunk] {
        let parser = EPUBParser()
        do {
            let metadata = try await parser.open(url: fileURL)
            var chunks: [AIDocumentChunk] = []

            for (idx, item) in metadata.spineItems.enumerated() {
                try Task.checkCancellation()
                guard let xhtml = try? await parser.contentForSpineItem(href: item.href) else { continue }
                let plain = EPUBTextExtractor.stripHTML(xhtml).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !plain.isEmpty else { continue }
                guard let locator = Locator.validated(bookFingerprint: fingerprint, href: item.href) else { continue }
                let sourceUnitID = "epub:\(item.href)"

                let chunk = AIDocumentChunk(
                    id: AIDocumentChunkFactory.stableID(
                        fingerprint: fingerprint,
                        sourceUnitID: sourceUnitID,
                        localStartUTF16: 0
                    ),
                    bookFingerprintKey: fingerprint.canonicalKey,
                    sourceUnitID: sourceUnitID,
                    sourceUnitIndex: idx,
                    text: plain,
                    locator: locator,
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

#if canImport(PDFKit)
@MainActor
private final class LocalPDFDocumentFacade: AIPDFDocumentFacading {
    let doc: PDFKit.PDFDocument?
    var isLocked: Bool { doc?.isLocked ?? false }
    init(url: URL) { self.doc = PDFKit.PDFDocument(url: url) }
    var pageCount: Int { doc?.pageCount ?? 0 }
    var currentPageIndex: Int? { nil }
    func text(forPage index: Int) async throws -> String {
        doc?.page(at: index)?.string ?? ""
    }
    func renderPageForOCR(index: Int, maxDimension: CGFloat) async throws -> CGImage? {
        guard let page = doc?.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let maxDim = max(bounds.width, bounds.height, 1)
        let scale = min(1.5, maxDimension / maxDim)
        let width = Int(max(1, bounds.width * scale))
        let height = Int(max(1, bounds.height * scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }
}
#endif

    private func extractPDFChunks(
        for book: LibraryBookItem,
        fingerprint: DocumentFingerprint,
        fileURL: URL
    ) async throws -> [AIDocumentChunk] {
        #if canImport(PDFKit)
        let facade = await MainActor.run { LocalPDFDocumentFacade(url: fileURL) }
        let (pageCount, isLocked) = await MainActor.run { (facade.pageCount, facade.isLocked) }
        guard pageCount > 0 else {
            throw NSError(domain: "vreader.semantic.indexer", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Failed to open PDF document: \(fileURL.lastPathComponent)"
            ])
        }
        guard !isLocked else {
            Self.log.info("Skipping locked PDF book: \(book.fingerprintKey)")
            return []
        }

        var chunks: [AIDocumentChunk] = []
        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()

            var pageText = (try? await facade.text(forPage: pageIndex))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var isOCR = false

            if pageText.count < 30, let ocrService {
                if let ocrResult = try? await ocrService.extractPageText(bookKey: fingerprint.canonicalKey, pageIndex: pageIndex, facade: facade) {
                    let recognized = ocrResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !recognized.isEmpty {
                        pageText = recognized
                        isOCR = true
                    }
                }
            }

            guard !pageText.isEmpty else { continue }
            guard let locator = Locator.validated(bookFingerprint: fingerprint, page: pageIndex) else { continue }
            let sourceUnitID = "pdf:page:\(pageIndex)"

            let chunk = AIDocumentChunk(
                id: AIDocumentChunkFactory.stableID(
                    fingerprint: fingerprint,
                    sourceUnitID: sourceUnitID,
                    localStartUTF16: 0
                ),
                bookFingerprintKey: fingerprint.canonicalKey,
                sourceUnitID: sourceUnitID,
                sourceUnitIndex: pageIndex,
                text: pageText,
                locator: locator,
                sourceLabel: "Page \(pageIndex + 1)",
                chapterTitle: nil,
                pageIndex: pageIndex,
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

    private func extractPlainTextChunks(
        for book: LibraryBookItem,
        fingerprint: DocumentFingerprint,
        fileURL: URL
    ) throws -> [AIDocumentChunk] {
        let plain = try ClosedBookTextExtractor.extractPlainText(url: fileURL)
        guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let sourcePrefix = book.format.lowercased() == "md" ? "md" : "txt"
        let segments = UTF16TextSegmenter.segments(in: plain)
        var chunks: [AIDocumentChunk] = []
        chunks.reserveCapacity(segments.count)

        for segment in segments {
            try Task.checkCancellation()
            let sourceUnitID = "\(sourcePrefix):segment:\(segment.index)"
            guard let locator = Locator.validated(
                bookFingerprint: fingerprint,
                charOffsetUTF16: segment.startUTF16,
                charRangeStartUTF16: segment.startUTF16,
                charRangeEndUTF16: segment.endUTF16
            ) else { continue }

            let chunk = AIDocumentChunk(
                id: AIDocumentChunkFactory.stableID(
                    fingerprint: fingerprint,
                    sourceUnitID: sourceUnitID,
                    localStartUTF16: 0
                ),
                bookFingerprintKey: fingerprint.canonicalKey,
                sourceUnitID: sourceUnitID,
                sourceUnitIndex: segment.index,
                text: segment.text,
                locator: locator,
                sourceLabel: book.title,
                chapterTitle: nil,
                pageIndex: nil,
                href: nil,
                localStartUTF16: 0,
                localEndUTF16: segment.text.utf16.count,
                globalStartUTF16: segment.startUTF16,
                globalEndUTF16: segment.endUTF16,
                isOCRDerived: false
            )
            chunks.append(chunk)
        }
        return chunks
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
