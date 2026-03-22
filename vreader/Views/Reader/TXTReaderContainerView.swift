// Purpose: SwiftUI container for the TXT reader. Composes TXTTextViewBridge
// (small files) or TXTChunkedReaderBridge (large files) with paged/scroll modes.
//
// @coordinates-with: TXTReaderViewModel.swift, TXTTextViewBridge.swift,
//   TXTChunkedReaderBridge.swift, TXTReaderContainerView+Helpers.swift,
//   TextReaderUIState.swift, HighlightCoordinator.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

/// Container view for the TXT reader screen.
struct TXTReaderContainerView: View {
    let fileURL: URL
    let viewModel: TXTReaderViewModel
    var settingsStore: ReaderSettingsStore?
    var modelContainer: ModelContainer?
    var ttsService: TTSService?

    @Environment(\.scenePhase) private var scenePhase
    /// Mirrors ReaderContainerView's chrome toggle so the bottom overlay hides with the nav bar.
    @State private var isChromeVisible = true

    /// Files with more UTF-16 code units than this use chunked rendering.
    static let largeFileThreshold = 500_000

    // MARK: - TXT-Specific State

    /// Pre-built attributed string for small files, constructed off the main thread.
    @State var preparedAttrString: NSAttributedString?
    /// True while the attributed string is being built for the first time.
    /// Subsequent rebuilds (e.g., settings changes) keep old content visible.
    @State private var isBuildingInitialAttrString = false
    /// Pre-split chunks for large files.
    @State private var textChunks: [String]?
    /// Cumulative UTF-16 start offsets per chunk.
    @State private var chunkStartOffsets: [Int]?
    /// Captured scroll position for one-shot restore. Set once after file opens.
    /// Using @State breaks the observation cycle that caused bug #15/#17:
    /// reading viewModel.currentOffsetUTF16 in body created a feedback loop.
    @State var initialRestoreOffset: Int?

    // MARK: - Shared UI State (Phase R3) + Highlight Coordination (Phase R4)

    @State var uiState = TextReaderUIState()
    @State var highlightRenderer: TextHighlightRenderer?
    @State var highlightCoordinator: HighlightCoordinator?
    /// TTS sentence highlighting + auto-scroll coordinator (features #40, #41).
    @State var ttsHighlightCoordinator: TTSHighlightCoordinator?

    /// Whether paged mode is active (small file + paged layout preference).
    var isPagedMode: Bool {
        settingsStore?.epubLayout == .paged && !isLargeFile
    }

    /// Whether the loaded text exceeds the large file threshold.
    private var isLargeFile: Bool {
        viewModel.totalTextLengthUTF16 > Self.largeFileThreshold
    }

    /// Composite key that triggers attributed string rebuild when text or config changes.
    /// Uses totalTextLengthUTF16 + totalWordCount (O(1)) instead of text.hashValue (O(n)).
    /// Includes theme colors so theme changes trigger rebuild (bug #29).
    private var attrStringKey: String {
        let hasText = viewModel.textContent != nil
        let len = viewModel.totalTextLengthUTF16
        let words = viewModel.totalWordCount
        let cfg = settingsStore?.txtViewConfig ?? TXTViewConfig()
        let textColorHash = cfg.textColor.hash
        let bgColorHash = cfg.backgroundColor.hash
        return "\(hasText)-\(len)-\(words)-\(cfg.fontSize)-\(cfg.fontName ?? "sys")-\(cfg.lineSpacing)-\(cfg.letterSpacing)-\(textColorHash)-\(bgColorHash)"
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading || isBuildingInitialAttrString {
                loadingView
            } else if let errorMessage = viewModel.errorMessage, viewModel.textContent == nil {
                errorView(message: errorMessage)
            } else if viewModel.textContent != nil && isLargeFile {
                // Large file → chunked renderer
                if let chunks = textChunks, let offsets = chunkStartOffsets {
                    chunkedReaderContent(chunks: chunks, offsets: offsets)
                } else {
                    loadingView
                }
            } else if let text = viewModel.textContent, let attrStr = preparedAttrString {
                // Small file → paged or scroll
                if isPagedMode, let nav = uiState.pageNavigator {
                    pagedReaderContent(text: text, attributedText: attrStr, navigator: nav)
                } else {
                    readerContent(text: text, attributedText: attrStr)
                }
            } else if viewModel.textContent != nil {
                loadingView
            } else {
                Color.clear
            }

            // Bottom overlay for session time, progress, and scrubber (bug #33, WI-004b)
            // Hidden when TTS is active to avoid overlap (bug #97)
            if viewModel.textContent != nil && !viewModel.isLoading && isChromeVisible
                && (ttsService?.state ?? .idle) == .idle {
                VStack(spacing: 0) {
                    Spacer()
                    ReadingProgressBar(
                        progress: $uiState.readingProgress,
                        onSeek: { seekValue in
                            let charOffset = ScrollProgressHelper.charOffsetFromProgress(
                                progress: seekValue,
                                totalLengthUTF16: viewModel.totalTextLengthUTF16
                            )
                            uiState.scrollToOffset = charOffset
                        },
                        isVisible: viewModel.totalTextLengthUTF16 > 0,
                        label: ScrollProgressHelper.percentageLabel(uiState.readingProgress),
                        settingsStore: settingsStore
                    )
                    ReaderBottomOverlay(
                        progress: viewModel.totalProgression,
                        sessionTime: viewModel.sessionTimeDisplay,
                        settingsStore: settingsStore,
                        accessibilityPrefix: "txt"
                    )
                }
            }
        }
        .task {
            await viewModel.open(url: fileURL)
            initialRestoreOffset = viewModel.currentOffsetUTF16
            // PERF: Create renderer/coordinator immediately, but defer DB restore
            let renderer = TextHighlightRenderer(uiState: uiState)
            highlightRenderer = renderer
            if let tts = ttsService {
                ttsHighlightCoordinator = TTSHighlightCoordinator(ttsService: tts, uiState: uiState)
            }
            // Defer highlight restore — don't block content display
            Task {
                if let container = modelContainer {
                    let persistence = PersistenceActor(modelContainer: container)
                    let coordinator = HighlightCoordinator(
                        renderer: renderer,
                        persistence: persistence,
                        bookFingerprintKey: viewModel.bookFingerprintKey
                    )
                    highlightCoordinator = coordinator
                    await coordinator.restoreAll()
                }
            }
        }
        .task(id: attrStringKey) {
            guard let text = viewModel.textContent else { return }
            let config = settingsStore?.txtViewConfig ?? TXTViewConfig()

            if text.utf16.count > Self.largeFileThreshold {
                // Large file: split into chunks (fast, no attributed string needed here)
                let isInitial = textChunks == nil
                if isInitial { isBuildingInitialAttrString = true }
                defer { if isInitial { isBuildingInitialAttrString = false } }

                let splitResult = await Task.detached(priority: .userInitiated) {
                    let chunks = TXTTextChunker.split(text: text, targetChunkSize: 16384)
                    var offsets: [Int] = []
                    offsets.reserveCapacity(chunks.count)
                    var cumulative = 0
                    for chunk in chunks {
                        offsets.append(cumulative)
                        cumulative += chunk.utf16.count
                    }
                    return (chunks, offsets)
                }.value
                guard !Task.isCancelled else { return }
                textChunks = splitResult.0
                chunkStartOffsets = splitResult.1
            } else {
                // Small file: build full attributed string
                let isInitial = preparedAttrString == nil
                if isInitial { isBuildingInitialAttrString = true }
                defer { if isInitial { isBuildingInitialAttrString = false } }

                let wrapped = await Task.detached(priority: .userInitiated) {
                    TXTAttributedStringBuilder.buildSendable(text: text, config: config)
                }.value
                guard !Task.isCancelled else { return }
                preparedAttrString = wrapped.value
                // Trigger pagination if paged mode is active (B08)
                if isPagedMode {
                    updatePaginationIfNeeded()
                }
            }
        }
        .onDisappear {
            let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            Task {
                await viewModel.close()
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                Task {
                    await viewModel.onBackground()
                    if bgTaskID != .invalid {
                        UIApplication.shared.endBackgroundTask(bgTaskID)
                    }
                }
            case .active:
                viewModel.onForeground()
            @unknown default:
                break
            }
        }
        .onChange(of: viewModel.totalProgression) { _, newValue in
            uiState.readingProgress = newValue ?? 0
            // Notify ReaderContainerView of the live position for AI panel.
            let locator = viewModel.makeLocator()
            NotificationCenter.default.post(
                name: .readerPositionDidChange, object: locator
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            isChromeVisible.toggle()
            // Pause auto page turner on user interaction (B10)
            uiState.autoPageTurner?.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNextPage)) { _ in
            guard isPagedMode else { return }
            uiState.pageNavigator?.nextPage()
            if let offset = uiState.syncPagedState() {
                viewModel.updateScrollPosition(charOffsetUTF16: offset)
            }
            // Pause auto page turner on user interaction (B10)
            uiState.autoPageTurner?.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPreviousPage)) { _ in
            guard isPagedMode else { return }
            uiState.pageNavigator?.previousPage()
            if let offset = uiState.syncPagedState() {
                viewModel.updateScrollPosition(charOffsetUTF16: offset)
            }
            // Pause auto page turner on user interaction (B10)
            uiState.autoPageTurner?.pause()
        }
        .onChange(of: settingsStore?.epubLayout) { _, _ in
            updatePaginationIfNeeded()
        }
        .onChange(of: settingsStore?.typography.fontSize) { _, _ in
            updatePaginationIfNeeded()
        }
        .onChange(of: settingsStore?.autoPageTurn) { _, newValue in
            uiState.updateAutoPageTurner(
                enabled: newValue ?? false,
                isPagedMode: isPagedMode,
                interval: settingsStore?.autoPageTurnInterval ?? 5.0
            )
        }
        .readerNotificationHandlers(
            deps: makeNotificationDeps(),
            uiState: uiState,
            highlightCoordinator: highlightCoordinator ?? makeNoOpCoordinator()
        )
        // highlightRemoved now handled by ReaderNotificationModifier (Phase R2)
        .accessibilityIdentifier("txtReaderContainer")
        .accessibilityValue(initialRestoreOffset.map { "restoredOffset:\($0)" } ?? "restoredOffset:none")
    }

    // MARK: - Subviews

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("txtReaderLoading")
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .accessibilityIdentifier("txtReaderError")
    }

    @ViewBuilder
    private func pagedReaderContent(
        text: String,
        attributedText: NSAttributedString,
        navigator: NativeTextPageNavigator
    ) -> some View {
        VStack(spacing: 0) {
            NativeTextPagedView(
                navigator: navigator,
                fullText: text,
                fullAttributedText: attributedText,
                config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
                currentPage: uiState.pagedCurrentPage,
                pageTurnAnimation: settingsStore?.pageTurnAnimation ?? .none
            )

            // Page indicator
            if navigator.totalPages > 0 {
                Text("Page \(uiState.pagedCurrentPage + 1) of \(navigator.totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("txtPageIndicator")
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("txtReaderPagedContent")
    }

    @ViewBuilder
    private func readerContent(text: String, attributedText: NSAttributedString) -> some View {
        TXTTextViewBridge(
            text: text,
            attributedText: attributedText,
            config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
            restoreOffset: initialRestoreOffset,
            scrollToOffset: uiState.scrollToOffset,
            highlightRange: uiState.highlightRange,
            highlightIsTemporary: uiState.highlightIsTemporary,
            persistedHighlights: uiState.persistedHighlightRanges,
            delegate: viewModel
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("txtReaderContent")
    }

}
#endif
