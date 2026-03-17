// Purpose: SwiftUI container for the Markdown reader. Composes the TXTTextViewBridge
// (with NSAttributedString) with loading/error overlays and reading session chrome.
// When layout is .paged, uses NativeTextPagedView for page-at-a-time rendering.
//
// Key decisions:
// - Owns MDReaderViewModel lifecycle (open on appear, close on disappear).
// - Delegates scroll/selection events from bridge to ViewModel for position persistence.
// - Shows loading spinner during file open.
// - Shows error message on failure.
// - Passes rendered NSAttributedString to bridge for rich display.
// - Paged mode (B08): uses NativeTextPageNavigator + NativeTextPagedView.
// - AutoPageTurner (B10): wired when autoPageTurn is enabled + paged layout.
// - PageTurnAnimator (B11): animation style from settingsStore.pageTurnAnimation.
//
// @coordinates-with: MDReaderViewModel.swift, TXTTextViewBridge.swift,
//   ReadingProgressBar.swift, ScrollProgressHelper.swift,
//   NativeTextPageNavigator.swift, NativeTextPagedView.swift,
//   AutoPageTurner.swift, PageTurnAnimator.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

/// Container view for the Markdown reader screen.
struct MDReaderContainerView: View {
    let fileURL: URL
    let viewModel: MDReaderViewModel
    var settingsStore: ReaderSettingsStore?
    var modelContainer: ModelContainer?

    @Environment(\.scenePhase) private var scenePhase
    /// Mirrors ReaderContainerView's chrome toggle so the bottom overlay hides with the nav bar.
    @State private var isChromeVisible = true

    /// Captured scroll position for one-shot restore. Set once after file opens.
    @State private var initialRestoreOffset: Int?
    /// Navigation target from search results. Updated via notification.
    @State private var scrollToOffset: Int?
    /// Match highlight range for search navigation (bug #43).
    @State private var highlightRange: NSRange?
    /// Whether the current highlight is temporary (search nav) or persistent (user-created).
    @State private var highlightIsTemporary: Bool = true
    /// Pending annotation info for the "Add Note" flow (bug #44).
    @State private var pendingAnnotationInfo: TextSelectionInfo?
    /// Text input for the annotation note.
    @State private var annotationNoteText: String = ""
    /// Persisted highlight ranges loaded from DB on file open (bug #55).
    @State private var persistedHighlightRanges: [NSRange] = []

    /// Current reading progress for the scrubber bar (0.0-1.0).
    /// Synced from viewModel.totalProgression via onChange.
    @State private var readingProgress: Double = 0

    // MARK: - Paged Mode State (B08, B10, B11)

    /// Page navigator for paged mode. Nil when in scroll mode.
    @State private var pageNavigator: NativeTextPageNavigator?
    /// Tracks the current page for SwiftUI reactivity.
    @State private var pagedCurrentPage: Int = 0
    /// Auto page turner instance (B10). Created when autoPageTurn is enabled.
    @State private var autoPageTurner: AutoPageTurner?

    /// Whether paged mode is active.
    private var isPagedMode: Bool {
        settingsStore?.epubLayout == .paged
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage, viewModel.renderedText == nil {
                errorView(message: errorMessage)
            } else if let attrStr = viewModel.renderedAttributedString {
                if isPagedMode, let nav = pageNavigator {
                    pagedReaderContent(attributedString: attrStr, navigator: nav)
                } else {
                    readerContent(attributedString: attrStr)
                }
            } else {
                // Not yet opened
                Color.clear
            }

            // Bottom overlay for progress, scrubber, and session time (WI-004b)
            if viewModel.renderedText != nil && !viewModel.isLoading && isChromeVisible {
                VStack(spacing: 0) {
                    Spacer()
                    ReadingProgressBar(
                        progress: $readingProgress,
                        onSeek: { seekValue in
                            let charOffset = ScrollProgressHelper.charOffsetFromProgress(
                                progress: seekValue,
                                totalLengthUTF16: viewModel.renderedTextLengthUTF16
                            )
                            scrollToOffset = charOffset
                        },
                        isVisible: viewModel.renderedTextLengthUTF16 > 0,
                        label: ScrollProgressHelper.percentageLabel(readingProgress),
                        settingsStore: settingsStore
                    )
                    ReaderBottomOverlay(
                        progress: viewModel.totalProgression,
                        sessionTime: viewModel.sessionTimeDisplay,
                        settingsStore: settingsStore,
                        accessibilityPrefix: "md"
                    )
                }
            }
        }
        .task {
            await viewModel.open(url: fileURL)
            initialRestoreOffset = viewModel.currentOffsetUTF16
            // Trigger pagination if paged mode is active (B08)
            if isPagedMode {
                updatePaginationIfNeeded()
            }
            // Load persisted highlights from DB for visual rendering (bug #55)
            if let container = modelContainer {
                let persistence = PersistenceActor(modelContainer: container)
                if let records = try? await persistence.fetchHighlights(
                    forBookWithKey: viewModel.bookFingerprintKey
                ) {
                    persistedHighlightRanges = records.compactMap { record in
                        guard let start = record.locator.charRangeStartUTF16,
                              let end = record.locator.charRangeEndUTF16,
                              end > start else { return nil }
                        return NSRange(location: start, length: end - start)
                    }
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
            readingProgress = newValue ?? 0
            // Notify ReaderContainerView of the live position for AI panel.
            let locator = viewModel.makeLocator()
            NotificationCenter.default.post(
                name: .readerPositionDidChange, object: locator
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            isChromeVisible.toggle()
            autoPageTurner?.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNextPage)) { _ in
            guard isPagedMode else { return }
            pageNavigator?.nextPage()
            syncPagedState()
            autoPageTurner?.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPreviousPage)) { _ in
            guard isPagedMode else { return }
            pageNavigator?.previousPage()
            syncPagedState()
            autoPageTurner?.pause()
        }
        .onChange(of: settingsStore?.epubLayout) { _, _ in
            updatePaginationIfNeeded()
        }
        .onChange(of: settingsStore?.typography.fontSize) { _, _ in
            updatePaginationIfNeeded()
        }
        .onChange(of: settingsStore?.autoPageTurn) { _, newValue in
            updateAutoPageTurner(enabled: newValue ?? false)
        }
        .readerNotificationHandlers(
            deps: makeNotificationDeps(),
            scrollToOffset: $scrollToOffset,
            highlightRange: $highlightRange,
            highlightIsTemporary: $highlightIsTemporary,
            persistedHighlightRanges: $persistedHighlightRanges,
            pendingAnnotationInfo: $pendingAnnotationInfo,
            annotationNoteText: $annotationNoteText
        )
        .accessibilityIdentifier("mdReaderContainer")
    }

    // MARK: - Notification Dependencies

    private func makeNotificationDeps() -> ReaderNotificationDeps {
        let container = modelContainer
        return ReaderNotificationDeps(
            bookFingerprintKey: viewModel.bookFingerprintKey,
            bookFingerprint: viewModel.bookFingerprint,
            bookmarkPersistence: container.map { PersistenceActor(modelContainer: $0) } ?? NoOpBookmarkStore(),
            highlightPersistence: container.map { PersistenceActor(modelContainer: $0) } ?? NoOpHighlightStore(),
            annotationPersistence: container.map { PersistenceActor(modelContainer: $0) } ?? NoOpAnnotationStore(),
            locatorFactory: { fp, start, end, text in
                LocatorFactory.mdRange(fingerprint: fp, charRangeStartUTF16: start, charRangeEndUTF16: end, sourceText: text)
            },
            sourceText: { [viewModel] in viewModel.renderedText },
            makeCurrentLocator: { [viewModel] in viewModel.makeLocator() },
            onNavigate: { [viewModel] offset in viewModel.updateScrollPosition(charOffsetUTF16: offset) },
            hapticFeedback: HapticFeedbackProvider()
        )
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
        .accessibilityIdentifier("mdReaderLoading")
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
        .accessibilityIdentifier("mdReaderError")
    }

    @ViewBuilder
    private func pagedReaderContent(
        attributedString: NSAttributedString,
        navigator: NativeTextPageNavigator
    ) -> some View {
        VStack(spacing: 0) {
            NativeTextPagedView(
                navigator: navigator,
                fullText: attributedString.string,
                fullAttributedText: attributedString,
                config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
                currentPage: pagedCurrentPage,
                pageTurnAnimation: settingsStore?.pageTurnAnimation ?? .none
            )

            if navigator.totalPages > 0 {
                Text("Page \(pagedCurrentPage + 1) of \(navigator.totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("mdPageIndicator")
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("mdReaderPagedContent")
    }

    @ViewBuilder
    private func readerContent(attributedString: NSAttributedString) -> some View {
        TXTTextViewBridge(
            text: attributedString.string,
            attributedText: attributedString,
            config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
            restoreOffset: initialRestoreOffset,
            scrollToOffset: scrollToOffset,
            highlightRange: highlightRange,
            highlightIsTemporary: highlightIsTemporary,
            persistedHighlights: persistedHighlightRanges,
            delegate: viewModel
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("mdReaderContent")
    }

    // MARK: - Paged Mode Helpers (B08, B10)

    private func updatePaginationIfNeeded() {
        guard isPagedMode,
              let attrStr = viewModel.renderedAttributedString,
              let settings = settingsStore else {
            autoPageTurner?.stop()
            pageNavigator = nil
            return
        }

        let nav = pageNavigator ?? NativeTextPageNavigator()
        nav.paginateAttributed(
            attributedText: attrStr,
            viewportSize: UIScreen.main.bounds.size
        )

        if pageNavigator == nil, let offset = initialRestoreOffset {
            nav.jumpToOffset(utf16Offset: offset)
        }

        pageNavigator = nav
        syncPagedState()

        if settings.autoPageTurn {
            updateAutoPageTurner(enabled: true)
        }
    }

    private func syncPagedState() {
        guard let nav = pageNavigator else { return }
        pagedCurrentPage = nav.currentPage
        if nav.totalPages > 1 {
            readingProgress = nav.progression
        }
        if let range = nav.currentPageCharRange {
            viewModel.updateScrollPosition(charOffsetUTF16: range.location)
        }
    }

    private func updateAutoPageTurner(enabled: Bool) {
        guard enabled, isPagedMode, let nav = pageNavigator else {
            autoPageTurner?.stop()
            return
        }

        let turner = autoPageTurner ?? AutoPageTurner()
        turner.interval = settingsStore?.autoPageTurnInterval ?? 5.0
        turner.start(navigator: nav)
        autoPageTurner = turner
    }
}
#endif
