// Purpose: Navigation container that dispatches to format-specific reader views.
// Determines reader type from book format and provides shared chrome.
//
// Key decisions:
// - Dispatches to format-specific reader based on BookFormat.
// - File URL resolved from fingerprintKey using the sandbox import convention.
// - DocumentFingerprint parsed from the canonical key string.
// - Format host views (TXTReaderHost, etc.) extracted to ReaderFormatHosts.swift (WI-004).
// - AnnotationsPanelView extracted to AnnotationsPanelView.swift (WI-004).
// - Provides navigation bar with back button, search, bookmark, annotations, settings.
// - TOC entries computed per format: EPUB from spine items, PDF from outline tree.
// - Search sheet wired with SearchService, SearchViewModel, and SearchView.
// - Book content is indexed for search on first open using format-specific extractors.
//
// @coordinates-with: ReaderFormatHosts.swift, AnnotationsPanelView.swift,
//   ReaderSettingsStore.swift, ReaderSettingsPanel.swift, DocumentFingerprint.swift,
//   SearchView.swift, SearchViewModel.swift, SearchService.swift, SearchIndexStore.swift

import SwiftUI
import SwiftData
import PDFKit
import os

/// Container view that dispatches to the correct format-specific reader.
struct ReaderContainerView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vreader",
        category: "Search"
    )

    let book: LibraryBookItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var settingsStore = ReaderSettingsStore()
    @State private var showSettings = false
    @State private var showAnnotationsPanel = false
    @State private var showSearch = false
    @State private var searchViewModel: SearchViewModel?
    @State private var searchService: SearchService?
    /// Controls whether the navigation bar chrome is visible. Tap content to toggle.
    @State private var isChromeVisible = true
    /// Computed TOC entries for the current book (format-specific).
    @State private var tocEntries: [TOCEntry] = []

    var body: some View {
        Group {
            if let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) {
                switch book.format.lowercased() {
                case "epub":
                    EPUBReaderHost(
                        fileURL: resolvedFileURL,
                        fingerprint: fingerprint,
                        modelContainer: modelContext.container,
                        settingsStore: settingsStore
                    )
                case "pdf":
                    PDFReaderHost(
                        fileURL: resolvedFileURL,
                        fingerprint: fingerprint,
                        modelContainer: modelContext.container
                    )
                case "txt":
                    TXTReaderHost(
                        fileURL: resolvedFileURL,
                        fingerprint: fingerprint,
                        modelContainer: modelContext.container,
                        settingsStore: settingsStore
                    )
                case "md":
                    MDReaderHost(
                        fileURL: resolvedFileURL,
                        fingerprint: fingerprint,
                        modelContainer: modelContext.container,
                        settingsStore: settingsStore
                    )
                default:
                    unsupportedFormatView(format: book.format.uppercased())
                }
            } else {
                fingerprintErrorView
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isChromeVisible.toggle()
            }
        }
        .accessibilityAction(named: isChromeVisible ? "Hide toolbar" : "Show toolbar") {
            withAnimation(.easeInOut(duration: 0.2)) {
                isChromeVisible.toggle()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(isChromeVisible ? .visible : .hidden, for: .navigationBar)
        .toolbarColorScheme(settingsStore.theme.preferredColorScheme, for: .navigationBar)
        .statusBarHidden(!isChromeVisible)
        .ignoresSafeArea(edges: isChromeVisible ? [] : [.top])
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back to library")
                .accessibilityIdentifier("readerBackButton")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search in book")
                .accessibilityIdentifier("readerSearchButton")

                Button {
                    NotificationCenter.default.post(
                        name: .readerBookmarkRequested, object: nil
                    )
                } label: {
                    Image(systemName: "bookmark")
                }
                .accessibilityLabel("Add bookmark")
                .accessibilityIdentifier("readerBookmarkButton")

                Button {
                    showAnnotationsPanel = true
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .accessibilityLabel("Bookmarks and annotations")
                .accessibilityIdentifier("readerAnnotationsButton")

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("Reading settings")
                .accessibilityIdentifier("readerSettingsButton")
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel(store: settingsStore)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAnnotationsPanel) {
            AnnotationsPanelView(
                bookFingerprintKey: book.fingerprintKey,
                modelContainer: modelContext.container,
                tocEntries: tocEntries,
                onNavigate: { locator in
                    NotificationCenter.default.post(
                        name: .readerNavigateToLocator,
                        object: locator
                    )
                },
                onDismiss: {
                    showAnnotationsPanel = false
                }
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSearch) {
            searchSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            guard searchService == nil,
                  let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) else {
                return
            }
            do {
                let store = try SearchIndexStore()
                let service = SearchService(store: store)
                searchService = service

                // Create ViewModel immediately so the search panel opens instantly.
                // Searching before indexing returns empty results (acceptable UX).
                let vm = SearchViewModel(
                    searchService: service,
                    bookFingerprint: fingerprint
                )
                searchViewModel = vm

                let alreadyIndexed = await service.isIndexed(fingerprint: fingerprint)
                if !alreadyIndexed {
                    await Self.indexBookContent(
                        service: service,
                        fileURL: resolvedFileURL,
                        fingerprint: fingerprint,
                        format: book.format.lowercased()
                    )
                    // Re-trigger search if user typed a query while indexing
                    vm.retriggerIfNeeded()
                }
            } catch {
                Self.logger.error("Search setup failed: \(error.localizedDescription)")
            }
        }
        .task {
            guard tocEntries.isEmpty,
                  let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) else {
                return
            }
            tocEntries = await Self.buildTOC(
                format: book.format.lowercased(),
                fileURL: resolvedFileURL,
                fingerprint: fingerprint
            )
        }
    }

    // MARK: - File URL Resolution

    /// Resolves the sandbox file URL using the same convention as BookImporter.
    private var resolvedFileURL: URL {
        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        let safeName = book.fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let bookFormat = BookFormat(rawValue: book.format.lowercased())
        let ext = bookFormat?.fileExtensions.first ?? book.format.lowercased()
        return booksDir
            .appendingPathComponent(safeName)
            .appendingPathExtension(ext)
    }

    // MARK: - Device ID

    /// Stable device identifier for reading position and session tracking.
    static let deviceId: String = {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        return UUID().uuidString
        #endif
    }()

    // MARK: - Search Indexing

    /// Extracts text from the book and indexes it for search.
    /// Runs on the calling task — use from a `.task` modifier for background execution.
    private static func indexBookContent(
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

    // MARK: - TOC Building

    /// Builds table of contents entries for the given book format.
    private static func buildTOC(
        format: String,
        fileURL: URL,
        fingerprint: DocumentFingerprint
    ) async -> [TOCEntry] {
        switch format {
        case "epub":
            let parser = EPUBParser()
            do {
                let metadata = try await parser.open(url: fileURL)
                await parser.close()
                return TOCBuilder.fromSpineItems(metadata.spineItems, fingerprint: fingerprint)
            } catch {
                await parser.close()
                return []
            }

        case "pdf":
            return await Task.detached {
                Self.extractPDFOutline(from: fileURL, fingerprint: fingerprint)
            }.value

        case "txt", "md":
            return []

        default:
            return []
        }
    }

    /// Extracts outline entries from a PDF document.
    /// Nonisolated so it can run off-main-actor in Task.detached.
    nonisolated private static func extractPDFOutline(
        from url: URL,
        fingerprint: DocumentFingerprint
    ) -> [TOCEntry] {
        guard let document = PDFDocument(url: url),
              let outline = document.outlineRoot else { return [] }
        var entries: [(title: String, level: Int, page: Int)] = []
        walkOutline(outline, document: document, level: 0, into: &entries)
        return TOCBuilder.fromPDFOutline(entries: entries, fingerprint: fingerprint)
    }

    nonisolated private static func walkOutline(
        _ node: PDFOutline,
        document: PDFDocument,
        level: Int,
        into entries: inout [(title: String, level: Int, page: Int)]
    ) {
        for i in 0..<node.numberOfChildren {
            guard let child = node.child(at: i) else { continue }
            if let label = child.label,
               let dest = child.destination,
               let page = dest.page {
                let pageIndex = document.index(for: page)
                entries.append((title: label, level: level, page: pageIndex))
            }
            walkOutline(child, document: document, level: level + 1, into: &entries)
        }
    }

    // MARK: - Sheets & Placeholders

    /// Search sheet — uses SearchView when search pipeline is ready.
    @ViewBuilder
    private var searchSheet: some View {
        if let searchViewModel {
            SearchView(
                viewModel: searchViewModel,
                onNavigate: { locator in
                    NotificationCenter.default.post(
                        name: .readerNavigateToLocator,
                        object: locator
                    )
                    showSearch = false
                },
                onDismiss: {
                    showSearch = false
                }
            )
            .accessibilityIdentifier("searchSheet")
        } else {
            NavigationStack {
                ProgressView("Preparing search…")
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                showSearch = false
                            }
                        }
                    }
            }
            .accessibilityIdentifier("searchSheet")
        }
    }

    private var fingerprintErrorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Unable to open this book.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("fingerprintErrorView")
    }

    private func unsupportedFormatView(format: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("\(format) reader coming soon")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("unsupportedFormatView")
    }
}


