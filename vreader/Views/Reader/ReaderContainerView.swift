// Purpose: Navigation container that dispatches to format-specific reader views.
// Determines reader type from book format and provides shared chrome.
//
// Key decisions:
// - Dispatches to format-specific reader based on BookFormat and ReadingMode.
// - When readingMode == .unified and format supports .unifiedReflow, shows placeholder (Phase B).
// - PDF always falls through to native (no .unifiedReflow capability).
// - File URL resolved from fingerprintKey using the sandbox import convention.
// - DocumentFingerprint parsed from the canonical key string.
// - Format host views (TXTReaderHost, etc.) extracted to ReaderFormatHosts.swift (WI-004).
// - AnnotationsPanelView extracted to AnnotationsPanelView.swift (WI-004).
// - Provides navigation bar with back button, search, bookmark, annotations, AI, settings.
// - TOC entries computed per format: EPUB from spine items, PDF from outline tree.
// - Search sheet wired with SearchService, SearchViewModel, and SearchView.
// - Book content is indexed for search on first open using format-specific extractors.
// - AI button conditionally shown when feature flag is ON and API key exists (WI-010).
// - AIReaderPanel presented as sheet for summarization, translation, and chat (WI-010, WI-012).
// - AITranslationViewModel created alongside AIAssistantViewModel for bilingual translation.
// - AIChatViewModel created with book fingerprint and book content context.
// - Book text loaded for AI; AIContextExtractor extracts ~2500 chars around current position.
// - EPUB text extracted via EPUBParser + EPUBTextExtractor.stripHTML (not raw ZIP read).
// - AI panel locator uses live reader position via .readerPositionDidChange notification.
//
// - ThemeBackgroundView shown behind reader content when useCustomBackground is ON.
//
// @coordinates-with: ReaderFormatHosts.swift, AnnotationsPanelView.swift,
//   ReaderSettingsStore.swift, ReaderSettingsPanel.swift, DocumentFingerprint.swift,
//   SearchView.swift, SearchViewModel.swift, SearchService.swift, SearchIndexStore.swift,
//   AIReaderPanel.swift, AIReaderAvailability.swift, AIAssistantViewModel.swift,
//   AITranslationViewModel.swift, AIChatViewModel.swift, ThemeBackgroundView.swift

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
    @State private var tapZoneStore = TapZoneStore()
    @State private var showSettings = false
    @State private var showAnnotationsPanel = false
    @State private var showSearch = false
    @State private var showAIPanel = false
    @State private var searchViewModel: SearchViewModel?
    @State private var searchService: SearchService?
    @State private var aiViewModel: AIAssistantViewModel?
    @State private var translationViewModel: AITranslationViewModel?
    @State private var chatViewModel: AIChatViewModel?
    /// Controls whether the navigation bar chrome is visible. Tap content to toggle.
    @State private var isChromeVisible = true
    /// Computed TOC entries for the current book (format-specific).
    @State private var tocEntries: [TOCEntry] = []

    var body: some View {
        ZStack {
            if settingsStore.useCustomBackground {
                ThemeBackgroundView(settingsStore: settingsStore)
            }

            Group {
                if let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) {
                    // TODO: Phase B12 — EPUB classifier will set isComplexEPUB at runtime.
                    // Currently BookFormat.capabilities always returns simple EPUB capabilities,
                    // so complex EPUBs get .unifiedReflow when they shouldn't. Acceptable for
                    // Phase 0 since Unified mode shows a placeholder anyway.
                    if settingsStore.readingMode == .unified
                        && resolvedBookFormat.capabilities.contains(.unifiedReflow) {
                        UnifiedPlaceholderView(settingsStore: settingsStore)
                    } else {
                        nativeReaderView(fingerprint: fingerprint)
                            .tapZoneOverlay(config: tapZoneStore.config)
                    }
                } else {
                    fingerprintErrorView
                }
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

                if isAIAvailable {
                    Button {
                        showAIPanel = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("AI Assistant")
                    .accessibilityIdentifier("readerAIButton")
                }

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("Reading settings")
                .accessibilityIdentifier("readerSettingsButton")
            }
        }
        .sheet(isPresented: $showAIPanel) {
            if let aiVM = aiViewModel,
               let transVM = translationViewModel,
               let chatVM = chatViewModel,
               let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) {
                AIReaderPanel(
                    viewModel: aiVM,
                    translationViewModel: transVM,
                    chatViewModel: chatVM,
                    locator: currentLocator ?? Locator(
                        bookFingerprint: fingerprint,
                        href: nil, progression: nil, totalProgression: nil, cfi: nil,
                        page: nil, charOffsetUTF16: nil,
                        charRangeStartUTF16: nil, charRangeEndUTF16: nil,
                        textQuote: nil, textContextBefore: nil, textContextAfter: nil
                    ),
                    textContent: currentTextContent,
                    format: resolvedBookFormat,
                    onDismiss: { showAIPanel = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .task {
            setupAIViewModelIfNeeded()
        }
        .task {
            await loadBookTextContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPositionDidChange)) { notification in
            guard let locator = notification.object as? Locator else { return }
            currentLocator = locator
            // Update chat VM with extracted context around new position
            chatViewModel?.bookContext = currentTextContent
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

                if !alreadyIndexed {
                    // Defer indexing to background (WI-F05)
                    let coordinator = BackgroundIndexingCoordinator(
                        searchService: service
                    )
                    await Self.enqueueBookIndexing(
                        coordinator: coordinator,
                        store: store,
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

    // MARK: - AI Integration

    /// Whether the AI assistant button should be visible.
    private var isAIAvailable: Bool {
        AIReaderAvailability.isAvailable(
            featureFlags: FeatureFlags.shared,
            keychainService: KeychainService()
        )
    }

    /// The resolved book format enum value.
    private var resolvedBookFormat: BookFormat {
        BookFormat(rawValue: book.format.lowercased()) ?? .txt
    }

    /// Full text content loaded from the book file. Used as the source for AI context extraction.
    @State private var loadedTextContent: String?

    /// Current reading position locator, updated via `.readerPositionDidChange` notification.
    /// Used by AIContextExtractor to determine which section to send as AI context.
    @State private var currentLocator: Locator?

    /// Text content for AI context. Extracts ~2500 chars around the current reading position
    /// using AIContextExtractor, instead of sending the entire book.
    private var currentTextContent: String {
        guard let loaded = loadedTextContent, !loaded.isEmpty else {
            return book.title.isEmpty ? "No content available" : book.title
        }
        let extractor = AIContextExtractor()
        if let locator = currentLocator {
            let extracted = extractor.extractContext(
                locator: locator,
                textContent: loaded,
                format: resolvedBookFormat
            )
            if !extracted.isEmpty { return extracted }
        }
        // Fallback: extract from beginning
        return String(loaded.prefix(extractor.targetCharacterCount))
    }

    /// Creates the AI ViewModels if AI features are available.
    private func setupAIViewModelIfNeeded() {
        guard aiViewModel == nil, isAIAvailable else { return }
        let flags = FeatureFlags.shared
        let keychain = KeychainService()
        let service = AIService(
            featureFlags: flags,
            consentManager: AIConsentManager(),
            keychainService: keychain,
            providerFactory: { apiKey, config in
                OpenAICompatibleProvider(
                    baseURL: config.endpoint,
                    apiKey: apiKey,
                    model: config.model
                )
            }
        )
        aiViewModel = AIAssistantViewModel(aiService: service)
        translationViewModel = AITranslationViewModel(aiService: service)

        let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey)
        let chatVM = AIChatViewModel(aiService: service, bookFingerprint: fingerprint)
        chatVM.bookContext = currentTextContent
        chatViewModel = chatVM
    }

    /// Loads text content from the book file for AI context extraction.
    /// For TXT/MD: reads the full text file.
    /// For PDF: extracts text from all pages via PDFKit.
    /// For EPUB: reads the raw content (best-effort text extraction).
    /// The full text is stored in `loadedTextContent`; AIContextExtractor then
    /// extracts only the relevant section (~2500 chars) around the current position.
    private func loadBookTextContent() async {
        guard loadedTextContent == nil else { return }
        let url = resolvedFileURL
        let format = book.format.lowercased()

        let text: String? = await Task.detached {
            switch format {
            case "txt", "md":
                return try? String(contentsOf: url, encoding: .utf8)

            case "pdf":
                guard let doc = PDFKit.PDFDocument(url: url) else { return nil }
                var pages: [String] = []
                for i in 0..<doc.pageCount {
                    if let page = doc.page(at: i), let text = page.string {
                        pages.append(text)
                    }
                }
                return pages.joined(separator: "\n\n")

            case "epub":
                // Extract text from EPUB spine items via EPUBParser + HTML stripping.
                // String(contentsOf:) on a .epub file reads the raw ZIP archive (garbage).
                let parser = EPUBParser()
                do {
                    let metadata = try await parser.open(url: url)
                    var textParts: [String] = []
                    for item in metadata.spineItems {
                        if let xhtml = try? await parser.contentForSpineItem(href: item.href) {
                            let plain = EPUBTextExtractor.stripHTML(xhtml)
                            let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                textParts.append(trimmed)
                            }
                        }
                    }
                    await parser.close()
                    return textParts.isEmpty ? nil : textParts.joined(separator: "\n\n")
                } catch {
                    await parser.close()
                    return nil
                }

            default:
                return nil
            }
        }.value

        if let text, !text.isEmpty {
            loadedTextContent = text
            // Update chat VM book context with extracted section (not full text)
            chatViewModel?.bookContext = currentTextContent
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

        case "txt":
            return []

        case "md":
            do {
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                return TOCBuilder.forMD(text: text, fingerprint: fingerprint)
            } catch {
                return []
            }

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

    /// Dispatches to the format-specific native reader.
    @ViewBuilder
    private func nativeReaderView(fingerprint: DocumentFingerprint) -> some View {
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


