// Purpose: Navigation container that dispatches to format-specific reader views.
// Determines reader type from book format and provides shared chrome.
//
// Key decisions:
// - Dispatches to format-specific reader based on BookFormat and ReadingMode.
// - When readingMode == .unified: TXT/MD use UnifiedTextRenderer (WI-B04); EPUB shows placeholder.
// - PDF always falls through to native (no .unifiedReflow capability).
// - File URL resolved from fingerprintKey using the sandbox import convention.
// - DocumentFingerprint parsed from the canonical key string.
// - Format host views (TXTReaderHost, etc.) extracted to ReaderFormatHosts.swift (WI-004).
// - AnnotationsPanelView extracted to AnnotationsPanelView.swift (WI-004).
// - Custom chrome overlay (ReaderChromeBar) replaces system nav bar for stable content layout.
// - TOC entries computed per format: EPUB from spine items, PDF from outline tree, TXT from Legado rules.
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
// @coordinates-with: ReaderChromeBar.swift, ReaderFormatHosts.swift,
//   AnnotationsPanelView.swift, ReaderSettingsStore.swift, ReaderSettingsPanel.swift,
//   DocumentFingerprint.swift, SearchView.swift, ThemeBackgroundView.swift,
//   ReaderAICoordinator.swift, ReaderSearchCoordinator.swift,
//   ReaderUnifiedCoordinator.swift, ReaderTOCBuilder.swift

import SwiftUI
import SwiftData
import os

/// Container view that dispatches to the correct format-specific reader.
struct ReaderContainerView: View {

    let book: LibraryBookItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var settingsStore = ReaderSettingsStore()
    @State private var tapZoneStore = TapZoneStore()
    @State private var showSettings = false
    @State private var showAnnotationsPanel = false
    @State private var showSearch = false
    @State private var showAIPanel = false
    @State private var showDictionary = false
    @State private var dictionaryWord: String = ""
    /// Controls whether the navigation bar chrome is visible. Tap content to toggle.
    @State private var isChromeVisible = true
    /// Computed TOC entries for the current book (format-specific).
    @State private var tocEntries: [TOCEntry] = []
    /// TTS service for read-aloud feature (WI-B03).
    @State private var ttsService = TTSService()
    /// Reading progress for the unified renderer (WI-B04).
    @State private var unifiedReadingProgress: Double = 0

    // MARK: - Coordinators

    @State private var aiCoordinator: ReaderAICoordinator?
    @State private var searchCoordinator = ReaderSearchCoordinator()
    @State private var unifiedCoordinator = ReaderUnifiedCoordinator()

    /// Shared content cache — loads book text once, shared across AI/search/TTS.
    @State private var contentCache = BookContentCache()
    /// Shared pagination cache for the unified renderer (B13).
    @State private var paginationCache = PaginationCache()

    var body: some View {
        ZStack {
            if settingsStore.useCustomBackground {
                ThemeBackgroundView(settingsStore: settingsStore)
            }

            Group {
                if let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) {
                    // TODO: Phase B12 — EPUB classifier will set isComplexEPUB at runtime.
                    // Currently BookFormat.capabilities always returns simple EPUB capabilities,
                    // so complex EPUBs get .unifiedReflow when they shouldn't.
                    // TXT/MD use UnifiedTextRenderer (WI-B04); EPUB unified shows placeholder.
                    if settingsStore.readingMode == .unified
                        && resolvedBookFormat.capabilities.contains(.unifiedReflow) {
                        unifiedReaderView(fingerprint: fingerprint)
                    } else {
                        // Native mode: tap handling lives in each UIKit bridge
                        // (UITapGestureRecognizer with shouldRecognizeSimultaneously).
                        // Do NOT add a SwiftUI overlay — it blocks scroll gestures. (bug #70)
                        nativeReaderView(fingerprint: fingerprint)
                    }
                } else {
                    fingerprintErrorView
                }
            }

            // Custom chrome overlay — floats on top of content, never changes layout. (bug #62 v3)
            if isChromeVisible {
                readerChromeOverlay
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // TTS control bar at the bottom (WI-B03)
            if ttsService.state != .idle {
                VStack {
                    Spacer()
                    TTSControlBar(
                        ttsService: ttsService,
                        settingsStore: settingsStore
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            toggleChrome()
        }
        .accessibilityAction(named: isChromeVisible ? "Hide toolbar" : "Show toolbar") {
            toggleChrome()
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!isChromeVisible)
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $showAIPanel) { aiSheet }
        .onReceive(NotificationCenter.default.publisher(for: .readerDefineRequested)) { notification in
            guard let info = notification.object as? TextSelectionInfo else { return }
            if let word = DictionaryLookup.extractWord(from: info.selectedText) {
                dictionaryWord = word
                showDictionary = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerTranslateRequested)) { notification in
            guard let info = notification.object as? TextSelectionInfo else { return }
            ensureAIReady()
            if let transVM = resolvedAICoordinator.translationViewModel {
                transVM.originalText = info.selectedText
            }
            showAIPanel = true
        }
        .sheet(isPresented: $showDictionary) {
            DictionarySheet(word: dictionaryWord)
        }
        // AI setup + text loading deferred until AI/TTS is invoked (bug #64)
        .onChange(of: showAIPanel) { _, isShowing in
            if isShowing { ensureAIReady() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPositionDidChange)) { notification in
            guard let locator = notification.object as? Locator else { return }
            resolvedAICoordinator.currentLocator = locator
            if resolvedAICoordinator.loadedTextContent != nil {
                resolvedAICoordinator.chatViewModel?.bookContext = resolvedAICoordinator.currentTextContent
            }
        }
        // Replacement rules only needed for unified mode (bug #64)
        .task {
            guard settingsStore.readingMode == .unified else { return }
            await loadReplacementRules()
        }
        .onChange(of: settingsStore.chineseConversion) { _, newDirection in
            var transforms = unifiedCoordinator.activeTransforms.filter { !($0 is SimpTradTransform) }
            if newDirection != .none {
                transforms.append(SimpTradTransform(direction: newDirection))
            }
            unifiedCoordinator.activeTransforms = transforms
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel(
                store: settingsStore,
                bookFingerprintKey: book.fingerprintKey,
                perBookBaseURL: Self.perBookSettingsBaseURL
            )
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
        // Search setup deferred until search sheet opens (bug #64)
        .onChange(of: showSearch) { _, isShowing in
            if isShowing { ensureSearchReady() }
        }
        // TOC deferred until annotations panel opens (bug #64)
        .onChange(of: showAnnotationsPanel) { _, isShowing in
            if isShowing { ensureTOCReady() }
        }
    }

    // MARK: - Resolved Helpers

    /// The resolved book format enum value.
    private var resolvedBookFormat: BookFormat {
        BookFormat(rawValue: book.format.lowercased()) ?? .txt
    }

    /// Lazily creates the AI coordinator on first access.
    private var resolvedAICoordinator: ReaderAICoordinator {
        if let existing = aiCoordinator { return existing }
        let coordinator = ReaderAICoordinator(
            fallbackTitle: book.title,
            bookFormat: resolvedBookFormat,
            fingerprintKey: book.fingerprintKey
        )
        // SwiftUI will apply the mutation at the end of the render pass
        DispatchQueue.main.async {
            aiCoordinator = coordinator
        }
        return coordinator
    }

    // MARK: - Chrome Toggle (bug #62 v3)

    /// Toggles chrome overlay visibility. Content is pixel-stable because we use
    /// a custom overlay (ReaderChromeBar) instead of the system nav bar.
    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isChromeVisible.toggle()
        }
    }

    // MARK: - TTS Integration (WI-B03)

    /// Starts or stops TTS read-aloud. If currently speaking, stops.
    /// Otherwise, loads text from the book file and starts speaking.
    private func startTTS() {
        ensureAIReady()
        let ai = resolvedAICoordinator
        if ttsService.state != .idle {
            ttsService.stop()
            return
        }

        // Use already-loaded text content if available
        if let text = ai.loadedTextContent, !text.isEmpty {
            let offset = ai.currentLocator?.charOffsetUTF16 ?? 0
            withAnimation(.easeInOut(duration: 0.2)) {
                ttsService.startSpeaking(text: text, fromOffset: offset)
            }
        } else {
            // Trigger text loading and start TTS when ready
            Task {
                await ai.loadBookTextContent(
                    fileURL: resolvedFileURL,
                    format: book.format.lowercased()
                )
                if let text = ai.loadedTextContent, !text.isEmpty {
                    let offset = ai.currentLocator?.charOffsetUTF16 ?? 0
                    withAnimation(.easeInOut(duration: 0.2)) {
                        ttsService.startSpeaking(text: text, fromOffset: offset)
                    }
                }
            }
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

    // MARK: - Per-Book Settings Base URL (A05)

    /// Directory where per-book settings JSON files are stored.
    static let perBookSettingsBaseURL: URL = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerBookSettings", isDirectory: true)
    }()

    // MARK: - Device ID

    /// Stable device identifier for reading position and session tracking.
    static let deviceId: String = {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        return UUID().uuidString
        #endif
    }()

    // MARK: - Deferred Setup (bug #64)

    /// Lazily sets up AI coordinator and loads book text for AI context.
    private func ensureAIReady() {
        let ai = resolvedAICoordinator
        ai.setupIfNeeded()
        guard ai.loadedTextContent == nil else { return }
        Task {
            let format = book.format.lowercased()
            if format == "txt" || format == "md" {
                if let text = await contentCache.getText(for: resolvedFileURL, format: format) {
                    ai.loadedTextContent = text
                    ai.chatViewModel?.bookContext = ai.currentTextContent
                } else {
                    await ai.loadBookTextContent(fileURL: resolvedFileURL, format: format)
                }
            } else {
                await ai.loadBookTextContent(fileURL: resolvedFileURL, format: format)
            }
        }
    }

    /// Lazily sets up search coordinator and indexing.
    private func ensureSearchReady() {
        guard searchCoordinator.searchService == nil,
              let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) else { return }
        Task {
            await searchCoordinator.setup(
                fingerprint: fingerprint,
                fileURL: resolvedFileURL,
                format: book.format.lowercased()
            )
        }
    }

    /// Lazily builds TOC entries.
    private func ensureTOCReady() {
        guard tocEntries.isEmpty,
              let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) else { return }
        Task {
            tocEntries = await ReaderTOCFactory.buildTOC(
                format: book.format.lowercased(),
                fileURL: resolvedFileURL,
                fingerprint: fingerprint
            )
        }
    }

    /// Loads replacement rules for the unified coordinator.
    private func loadReplacementRules() async {
        let bookKey = book.fingerprintKey
        let container = modelContext.container
        let rules: [ReplacementRuleDescriptor] = await Task.detached {
            let ctx = ModelContext(container)
            let descriptor = FetchDescriptor<ContentReplacementRule>(
                sortBy: [SortDescriptor(\.order)]
            )
            let allRules = (try? ctx.fetch(descriptor)) ?? []
            return allRules
                .filter { $0.enabled && ($0.scopeKey.isEmpty || $0.scopeKey == bookKey) }
                .map { ReplacementRuleDescriptor(
                    pattern: $0.pattern,
                    replacement: $0.replacement,
                    isRegex: $0.isRegex,
                    enabled: $0.enabled,
                    order: $0.order
                ) }
        }.value

        var transforms: [any TextTransform] = []
        if !rules.isEmpty {
            transforms.append(ReplacementTransform(rules: rules))
        }
        if settingsStore.chineseConversion != .none {
            transforms.append(SimpTradTransform(direction: settingsStore.chineseConversion))
        }
        unifiedCoordinator.activeTransforms = transforms
    }

    // MARK: - Sheets & Placeholders

    /// Search sheet — uses SearchView when search pipeline is ready.
    @ViewBuilder
    private var searchSheet: some View {
        if let searchViewModel = searchCoordinator.searchViewModel {
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

    /// Dispatches to the unified reflow engine for supported formats,
    /// or falls back to native reader for complex content.
    /// - TXT: plain text, no formatting.
    /// - MD: attributed text with bold/italic/headings (WI-B05).
    /// - EPUB (simple): HTML converted to attributed text (WI-B07).
    /// - EPUB (complex): falls back to native WKWebView reader (Phase B Audit fix).
    @ViewBuilder
    private func unifiedReaderView(fingerprint: DocumentFingerprint) -> some View {
        switch book.format.lowercased() {
        case "txt":
            if let text = unifiedCoordinator.textContent {
                UnifiedTextRenderer(
                    text: text,
                    settingsStore: settingsStore,
                    readingProgress: $unifiedReadingProgress,
                    paginationCache: paginationCache,
                    documentFingerprint: fingerprint.canonicalKey
                )
                .tapZoneOverlay(config: tapZoneStore.config)
            } else {
                ProgressView("Loading\u{2026}")
                    .task { await unifiedCoordinator.loadTextContent(fileURL: resolvedFileURL) }
            }
        case "md":
            if let text = unifiedCoordinator.textContent {
                UnifiedTextRenderer(
                    text: text,
                    settingsStore: settingsStore,
                    readingProgress: $unifiedReadingProgress,
                    attributedText: unifiedCoordinator.attributedText,
                    paginationCache: paginationCache,
                    documentFingerprint: fingerprint.canonicalKey
                )
                .tapZoneOverlay(config: tapZoneStore.config)
            } else {
                ProgressView("Loading\u{2026}")
                    .task { await unifiedCoordinator.loadMDContent(fileURL: resolvedFileURL) }
            }
        case "epub":
            if let text = unifiedCoordinator.textContent {
                VStack(spacing: 0) {
                    // Issue 10: Show warning banner when some chapters were skipped
                    if let warning = unifiedCoordinator.epubLoadWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))
                            .accessibilityIdentifier("epubUnifiedLoadWarning")
                    }
                    UnifiedTextRenderer(
                        text: text,
                        settingsStore: settingsStore,
                        readingProgress: $unifiedReadingProgress,
                        attributedText: unifiedCoordinator.attributedText,
                        paginationCache: paginationCache,
                        documentFingerprint: fingerprint.canonicalKey
                    )
                    .tapZoneOverlay(config: tapZoneStore.config)
                }
            } else if unifiedCoordinator.epubLoadComplete {
                // EPUB has complex chapters — fall back to native WKWebView reader.
                // No tapZoneOverlay — WKWebView has its own JS click handler. (bug #70)
                nativeReaderView(fingerprint: fingerprint)
            } else {
                ProgressView("Loading\u{2026}")
                    .task { await unifiedCoordinator.loadEPUBContent(fileURL: resolvedFileURL) }
            }
        default:
            UnifiedPlaceholderView(settingsStore: settingsStore)
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

    // MARK: - Custom Chrome Overlay (bug #62 v3)

    private var readerChromeOverlay: some View {
        ReaderChromeBar(
            onBack: { dismiss() },
            onSearch: { showSearch = true },
            onBookmark: {
                NotificationCenter.default.post(name: .readerBookmarkRequested, object: nil)
            },
            onAnnotations: { showAnnotationsPanel = true },
            onAI: resolvedAICoordinator.isAIAvailable ? { showAIPanel = true } : nil,
            onTTS: resolvedBookFormat.capabilities.contains(.tts) ? { startTTS() } : nil,
            onSettings: { showSettings = true },
            backgroundColor: Color(settingsStore.theme.backgroundColor),
            foregroundColor: Color(settingsStore.theme.textColor),
            ttsActive: ttsService.state != .idle
        )
    }

    // MARK: - AI Sheet

    @ViewBuilder
    private var aiSheet: some View {
        let ai = resolvedAICoordinator
        if let aiVM = ai.aiViewModel,
           let transVM = ai.translationViewModel,
           let chatVM = ai.chatViewModel,
           let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) {
            AIReaderPanel(
                viewModel: aiVM,
                translationViewModel: transVM,
                chatViewModel: chatVM,
                locator: ai.currentLocator ?? Locator(
                    bookFingerprint: fingerprint,
                    href: nil, progression: nil, totalProgression: nil, cfi: nil,
                    page: nil, charOffsetUTF16: nil,
                    charRangeStartUTF16: nil, charRangeEndUTF16: nil,
                    textQuote: nil, textContextBefore: nil, textContextAfter: nil
                ),
                textContent: ai.currentTextContent,
                format: resolvedBookFormat,
                onDismiss: { showAIPanel = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}


