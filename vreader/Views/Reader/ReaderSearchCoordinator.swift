// Purpose: Manages search service lifecycle, search VM creation, and book indexing.
// Extracted from ReaderContainerView to reduce file size (pure refactor).
//
// @coordinates-with ReaderContainerView.swift, SearchService.swift, SearchViewModel.swift,
//   SearchIndexStore.swift, BackgroundIndexingCoordinator.swift

import Foundation
import os

/// Owns the search pipeline state: SearchService, SearchViewModel, and indexing logic.
@Observable
@MainActor
final class ReaderSearchCoordinator {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vreader",
        category: "Search"
    )

    /// The search service instance. Nil until setup completes.
    private(set) var searchService: SearchService?
    /// The search view model. Nil until setup completes.
    private(set) var searchViewModel: SearchViewModel?

    /// Sets up the search pipeline for a book:
    /// creates the persistent index store, SearchService, and SearchViewModel,
    /// then enqueues background indexing if the book is not already indexed.
    func setup(
        fingerprint: DocumentFingerprint,
        fileURL: URL,
        format: String
    ) async {
        guard searchService == nil else { return }
        do {
            // Use persistent file-backed index (WI-F06)
            let store = try Self.makePersistentStore()
            let service = SearchService(store: store)
            searchService = service

            // Create ViewModel immediately so the search panel opens instantly.
            // Searching before indexing returns empty results (acceptable UX).
            let vm = SearchViewModel(
                searchService: service,
                bookFingerprint: fingerprint
            )
            searchViewModel = vm

            // Check persistent index -- skip if already indexed (WI-F06)
            let alreadyPersisted = store.isBookIndexed(
                fingerprintKey: fingerprint.canonicalKey
            )
            let inMemoryIndexed = await service.isIndexed(fingerprint: fingerprint)
            let alreadyIndexed = alreadyPersisted || inMemoryIndexed

            if alreadyIndexed {
                // Restore persisted segment offsets so search results have valid
                // locators without re-indexing. (bug #61)
                if let offsets = store.getSegmentBaseOffsets(
                    fingerprintKey: fingerprint.canonicalKey
                ) {
                    await service.restoreSegmentOffsets(
                        fingerprint: fingerprint,
                        offsets: offsets
                    )
                }
            } else {
                // Defer indexing to background (WI-F05)
                let coordinator = BackgroundIndexingCoordinator(
                    searchService: service
                )
                await Self.enqueueBookIndexing(
                    coordinator: coordinator,
                    store: store,
                    fileURL: fileURL,
                    fingerprint: fingerprint,
                    format: format
                )
                // Re-trigger search if user typed a query while indexing
                vm.retriggerIfNeeded()
            }
        } catch {
            Self.logger.error("Search setup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Persistent Search Index (WI-F06)

    /// Creates a persistent file-backed SearchIndexStore.
    /// Falls back to in-memory if file creation fails.
    private static func makePersistentStore() throws -> SearchIndexStore {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SearchIndex", isDirectory: true)
        let dbPath = dir.appendingPathComponent("search.sqlite3")
        do {
            let core = try SearchIndexCore(databasePath: dbPath.path)
            return try SearchIndexStore(core: core)
        } catch {
            logger.warning("Persistent index failed, using in-memory: \(error.localizedDescription)")
            return try SearchIndexStore()
        }
    }

    /// Extracts text units and enqueues them for background indexing (WI-F05).
    private static func enqueueBookIndexing(
        coordinator: BackgroundIndexingCoordinator,
        store: SearchIndexStore,
        fileURL: URL,
        fingerprint: DocumentFingerprint,
        format: String
    ) async {
        do {
            switch format {
            case "txt":
                let extractor = TXTTextExtractor()
                let result = try await extractor.extractWithOffsets(from: fileURL)
                await coordinator.enqueueIndexing(
                    fingerprint: fingerprint,
                    textUnits: result.textUnits,
                    segmentBaseOffsets: result.segmentBaseOffsets
                )
                // Persist segment offsets for future sessions
                if !result.segmentBaseOffsets.isEmpty {
                    store.setSegmentBaseOffsets(
                        fingerprintKey: fingerprint.canonicalKey,
                        offsets: result.segmentBaseOffsets
                    )
                }

            case "md":
                let extractor = MDTextExtractor()
                let result = try await extractor.extractWithOffsets(from: fileURL)
                await coordinator.enqueueIndexing(
                    fingerprint: fingerprint,
                    textUnits: result.textUnits,
                    segmentBaseOffsets: result.segmentBaseOffsets
                )
                if !result.segmentBaseOffsets.isEmpty {
                    store.setSegmentBaseOffsets(
                        fingerprintKey: fingerprint.canonicalKey,
                        offsets: result.segmentBaseOffsets
                    )
                }

            case "pdf":
                let extractor = PDFTextExtractor()
                let units = try await extractor.extractTextUnits(
                    from: fileURL, fingerprint: fingerprint
                )
                await coordinator.enqueueIndexing(
                    fingerprint: fingerprint,
                    textUnits: units,
                    segmentBaseOffsets: nil
                )

            case "epub":
                let parser = EPUBParser()
                do {
                    let metadata = try await parser.open(url: fileURL)
                    let extractor = EPUBTextExtractor()
                    let units = try await extractor.extractFromParser(
                        parser, metadata: metadata
                    )
                    await parser.close()
                    await coordinator.enqueueIndexing(
                        fingerprint: fingerprint,
                        textUnits: units,
                        segmentBaseOffsets: nil
                    )
                } catch {
                    await parser.close()
                    throw error
                }

            default:
                break
            }
        } catch {
            Self.logger.error(
                "Background index enqueue failed for \(format): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Search Indexing (Legacy)

    /// Extracts text from the book and indexes it for search.
    /// Runs on the calling task -- use from a `.task` modifier for background execution.
    static func indexBookContent(
        service: SearchService,
        fileURL: URL,
        fingerprint: DocumentFingerprint,
        format: String
    ) async {
        do {
            switch format {
            case "txt":
                let extractor = TXTTextExtractor()
                let result = try await extractor.extractWithOffsets(from: fileURL)
                try await service.indexBook(
                    fingerprint: fingerprint,
                    textUnits: result.textUnits,
                    segmentBaseOffsets: result.segmentBaseOffsets
                )

            case "md":
                let extractor = MDTextExtractor()
                let result = try await extractor.extractWithOffsets(from: fileURL)
                try await service.indexBook(
                    fingerprint: fingerprint,
                    textUnits: result.textUnits,
                    segmentBaseOffsets: result.segmentBaseOffsets
                )

            case "pdf":
                let extractor = PDFTextExtractor()
                let units = try await extractor.extractTextUnits(
                    from: fileURL, fingerprint: fingerprint
                )
                try await service.indexBook(
                    fingerprint: fingerprint,
                    textUnits: units,
                    segmentBaseOffsets: nil
                )

            case "epub":
                let parser = EPUBParser()
                do {
                    let metadata = try await parser.open(url: fileURL)
                    let extractor = EPUBTextExtractor()
                    let units = try await extractor.extractFromParser(
                        parser, metadata: metadata
                    )
                    await parser.close()
                    try await service.indexBook(
                        fingerprint: fingerprint,
                        textUnits: units,
                        segmentBaseOffsets: nil
                    )
                } catch {
                    await parser.close()
                    throw error
                }

            default:
                break
            }
        } catch {
            Self.logger.error("Search indexing failed for \(format): \(error.localizedDescription)")
        }
    }
}
