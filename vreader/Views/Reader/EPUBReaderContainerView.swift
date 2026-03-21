// Purpose: SwiftUI container for the EPUB reader. Composes the EPUBWebViewBridge
// with loading/error overlays, chapter navigation, reading progress bar, reading session chrome,
// and text selection action dialog with highlight persistence and restore.
//
// Key decisions:
// - Owns EPUBReaderViewModel lifecycle (open on appear, close on disappear).
// - Fetches resourceBaseURL from parser for content URL resolution (hrefs relative to opfDir).
// - Fetches extractedRootURL from parser for WKWebView allowingReadAccessTo (wider access).
// - Bottom overlay shows chapter navigation buttons, reading progress bar, and session time.
// - ReadingProgressBar wired via EPUBProgressCalculator for spine-aware progress (WI-004d).
// - Scroll progress from WKWebView feeds back to ViewModel.updatePosition.
// - WKWebView load errors surfaced via webViewError state.
// - Text selection triggers confirmationDialog with Highlight/Note/Copy actions.
// - "Add Note" opens a TextEditor sheet and persists highlight with note text.
// - Highlight action persists via PersistenceActor and injects CSS highlight JS.
// - Saved highlights are restored on page load via onPageDidFinishLoad callback.
// - Posts .readerPositionDidChange notification for AI panel live locator.
//
// @coordinates-with: EPUBReaderViewModel.swift, EPUBWebViewBridge.swift,
//   EPUBParserProtocol.swift, EPUBProgressCalculator.swift, ReadingProgressBar.swift,
//   EPUBHighlightBridge.swift, EPUBHighlightActions.swift, HighlightPersisting.swift,
//   EPUBPaginationHelper.swift, BasePageNavigator.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

/// Container view for the EPUB reader screen.
struct EPUBReaderContainerView: View {
    let fileURL: URL
    let viewModel: EPUBReaderViewModel
    let parser: any EPUBParserProtocol
    var settingsStore: ReaderSettingsStore?
    var modelContainer: ModelContainer?

    /// OPF directory — spine hrefs are resolved relative to this.
    @State private var resourceBase: URL?
    /// Extracted root directory — passed to WKWebView for file access.
    @State private var extractedRoot: URL?
    @State private var contentURL: URL?
    @State private var webViewError: String?
    @State private var openTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Mirrors ReaderContainerView's chrome toggle so the bottom overlay hides with the nav bar.
    @State private var isChromeVisible = true
    /// Overall reading progress (0.0-1.0) computed from spine index + scroll fraction.
    @State private var readingProgress: Double = 0
    /// Scroll fraction to pass to EPUBWebViewBridge for intra-chapter seeking.
    @State private var seekScrollFraction: Double?
    /// Pending text selection event for the highlight action dialog.
    @State private var pendingSelectionEvent: ReaderSelectionEvent?
    /// Whether the highlight action sheet is visible.
    @State private var showHighlightSheet = false
    /// JavaScript to inject into WKWebView (e.g., highlight CSS after persist).
    @State private var pendingHighlightJS: String?
    /// Whether the note input sheet is visible.
    @State private var showNoteSheet = false
    /// Text input for the note being added.
    @State private var noteText = ""
    /// Page navigator for paged layout (WI-B06).
    @State private var pageNavigator = BasePageNavigator()
    /// Current page in paged mode (drives bridge navigation).
    @State private var currentPaginationPage: Int?
    /// Phase R4: highlight renderer and coordinator.
    @State private var highlightRenderer = EPUBHighlightRenderer()
    @State private var highlightCoordinator: HighlightCoordinator?

    /// Whether paged layout is active.
    private var isPaged: Bool {
        settingsStore?.epubLayout == .paged
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage, viewModel.metadata == nil {
                errorView(message: errorMessage)
            } else if let webViewError {
                errorView(message: webViewError)
            } else if let contentURL, let extractedRoot {
                readerContent(contentURL: contentURL, accessRoot: extractedRoot)
            } else if viewModel.metadata != nil {
                // Metadata loaded but content URL not yet resolved
                loadingView
            } else {
                Color.clear
            }

            // Bottom navigation overlay (Issue 9: spacing: 0 to match PDF/TXT containers)
            if viewModel.metadata != nil, !viewModel.isLoading, isChromeVisible {
                VStack(spacing: 0) {
                    Spacer()
                    bottomOverlay
                }
            }
        }
        .task {
            // Phase R4: set up highlight renderer + coordinator
            highlightRenderer.onInjectJS = { [self] js in
                pendingHighlightJS = js
            }
            if let container = modelContainer {
                let persistence = PersistenceActor(modelContainer: container)
                highlightCoordinator = HighlightCoordinator(
                    renderer: highlightRenderer,
                    persistence: persistence,
                    bookFingerprintKey: viewModel.bookFingerprintKey
                )
            }

            let task = Task {
                await viewModel.open(url: fileURL)
                guard !Task.isCancelled else { return }
                // Resolve base directories and initial content URL
                guard viewModel.metadata != nil,
                      let firstItem = viewModel.currentPosition else { return }
                do {
                    let base = try await parser.resourceBaseURL()
                    let root = try await parser.extractedRootURL()
                    guard !Task.isCancelled else { return }
                    resourceBase = base
                    extractedRoot = root
                    // Restore intra-chapter scroll position (bug #58).
                    // The restored position includes progression (0.0-1.0)
                    // which must be passed to EPUBWebViewBridge as seekScrollFraction
                    // so the bridge scrolls to the saved offset after loading.
                    if firstItem.progression > 0 {
                        seekScrollFraction = firstItem.progression
                    }
                    contentURL = base.appendingPathComponent(firstItem.href)
                } catch {
                    if !Task.isCancelled {
                        webViewError = "Failed to resolve book resources."
                    }
                }
            }
            openTask = task
            await task.value
        }
        .onDisappear {
            openTask?.cancel()
            openTask = nil
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
        .onReceive(NotificationCenter.default.publisher(for: .readerBookmarkRequested)) { _ in
            guard let container = modelContainer,
                  let locator = viewModel.makeCurrentLocator() else { return }
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                try? await persistence.addBookmark(
                    locator: locator,
                    title: nil,
                    toBookWithKey: viewModel.bookFingerprintKey
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            isChromeVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNextPage)) { _ in
            guard isPaged else { return }
            pageNavigator.nextPage()
            currentPaginationPage = pageNavigator.currentPage
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPreviousPage)) { _ in
            guard isPaged else { return }
            pageNavigator.previousPage()
            currentPaginationPage = pageNavigator.currentPage
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNavigateToLocator)) { notification in
            guard let locator = notification.object as? Locator,
                  let href = locator.href,
                  let meta = viewModel.metadata,
                  let base = resourceBase else { return }
            if let spineIndex = meta.spineItems.firstIndex(where: { $0.href == href }) {
                viewModel.navigateToSpine(index: spineIndex)
                webViewError = nil
                // Issue 6: Reset pagination on locator navigation (same as chapter nav).
                pageNavigator.reset()
                currentPaginationPage = nil
                // Issue 3: Use locator.progression to scroll within the chapter.
                // This reuses the existing WI-004d scroll-to-fraction mechanism so
                // the WebView lands at the correct position, not chapter top.
                if let progression = locator.progression, progression > 0 {
                    seekScrollFraction = progression
                } else {
                    seekScrollFraction = nil
                }
                contentURL = base.appendingPathComponent(href)
                // Inject search highlight JS after page loads (bug #43)
                // Issue 4: Pass progression so JS scrolls before find()
                if let textQuote = locator.textQuote {
                    let js = EPUBHighlightBridge.searchHighlightJS(
                        textQuote: textQuote,
                        progression: locator.progression
                    )
                    if !js.isEmpty {
                        pendingHighlightJS = js
                    }
                }
            }
        }
        // Remove highlight visual when deleted from annotations panel (bug #78)
        // Phase R4b: delegate to coordinator (renderer generates remove JS)
        .onReceive(NotificationCenter.default.publisher(for: .readerHighlightRemoved)) { notification in
            guard let idString = notification.object as? String,
                  let highlightId = UUID(uuidString: idString) else { return }
            if let coordinator = highlightCoordinator {
                Task { await coordinator.handleRemoval(highlightId: highlightId) }
            } else {
                // Fallback: direct JS injection if coordinator not ready
                pendingHighlightJS = EPUBHighlightBridge.removeHighlightJS(id: idString)
            }
        }
        .confirmationDialog(
            "Text Selection",
            isPresented: $showHighlightSheet,
            titleVisibility: .visible
        ) {
            Button("Highlight") {
                guard let event = pendingSelectionEvent,
                      let container = modelContainer else { return }
                handleHighlightAction(event: event, container: container)
            }
            Button("Add Note") {
                noteText = ""
                showNoteSheet = true
            }
            Button("Copy") {
                guard let event = pendingSelectionEvent else { return }
                UIPasteboard.general.string = event.selectedText
                pendingSelectionEvent = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSelectionEvent = nil
            }
        }
        .sheet(isPresented: $showNoteSheet) {
            noteInputSheet
        }
        .accessibilityIdentifier("epubReaderContainer")
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
        .accessibilityIdentifier("epubReaderLoading")
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
        .accessibilityIdentifier("epubReaderError")
    }

    @ViewBuilder
    private func readerContent(contentURL: URL, accessRoot: URL) -> some View {
        EPUBWebViewBridge(
            contentURL: contentURL,
            baseDirectory: accessRoot,
            themeCSS: settingsStore.map {
                $0.theme.epubOverrideCSS(fontSize: $0.typography.fontSize)
            },
            scrollFraction: seekScrollFraction,
            currentHref: viewModel.currentPosition?.href,
            onProgressChange: { scrollFraction in
                guard let position = viewModel.currentPosition,
                      let metadata = viewModel.metadata else { return }
                let spineIndex = metadata.spineItems.firstIndex(
                    where: { $0.href == position.href }
                ) ?? 0
                let totalProg = EPUBProgressCalculator.progress(
                    spineIndex: spineIndex,
                    scrollFraction: scrollFraction,
                    totalSpineItems: metadata.spineCount
                )
                readingProgress = totalProg
                let newPosition = EPUBPosition(
                    href: position.href,
                    progression: scrollFraction,
                    totalProgression: totalProg,
                    cfi: nil
                )
                viewModel.updatePosition(newPosition)
                // Notify ReaderContainerView of the live position for AI panel.
                if let locator = viewModel.makeCurrentLocator() {
                    NotificationCenter.default.post(
                        name: .readerPositionDidChange, object: locator
                    )
                }
            },
            onLoadError: { error in
                webViewError = error
            },
            onSelectionEvent: { event in
                pendingSelectionEvent = event
                showHighlightSheet = true
            },
            onPageDidFinishLoad: { evaluateJS in
                restoreHighlightsOnLoad(evaluateJS: evaluateJS)
            },
            pendingJS: pendingHighlightJS,
            onPendingJSCompleted: {
                pendingHighlightJS = nil
            },
            isPaged: isPaged,
            paginationPage: currentPaginationPage,
            onPaginationReady: { totalPages in
                pageNavigator.totalPages = totalPages
            }
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("epubReaderContent")
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            // Reading progress scrubber bar
            ReadingProgressBar(
                progress: $readingProgress,
                onSeek: { handleProgressSeek($0) },
                discreteSteps: epubDiscreteSteps,
                isVisible: true,
                label: epubProgressLabel,
                settingsStore: settingsStore
            )

            // Navigation controls row
            HStack {
                Button {
                    navigateChapter(offset: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(viewModel.currentSpineIndex <= 0)
                .accessibilityLabel("Previous chapter")
                .accessibilityIdentifier("epubPrevChapter")

                Spacer()

                if let title = currentChapterTitle {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let sessionTime = viewModel.sessionTimeDisplay {
                    Text(sessionTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("epubSessionTime")
                }

                Spacer()

                Button {
                    navigateChapter(offset: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(
                    viewModel.currentSpineIndex >= (viewModel.metadata?.spineCount ?? 1) - 1
                )
                .accessibilityLabel("Next chapter")
                .accessibilityIdentifier("epubNextChapter")
            }
            .foregroundColor(Color(settingsStore?.theme.secondaryTextColor ?? ReaderTheme.default.secondaryTextColor))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(settingsStore?.theme.backgroundColor ?? ReaderTheme.default.backgroundColor).opacity(0.92))
        .accessibilityIdentifier("epubBottomOverlay")
    }

    // MARK: - Progress Bar

    /// Discrete steps for the progress bar: spine count for multi-chapter, nil for single/empty.
    private var epubDiscreteSteps: Int? {
        guard let meta = viewModel.metadata else { return nil }
        return EPUBProgressCalculator.discreteSteps(totalSpineItems: meta.spineCount)
    }

    /// "Chapter X of Y" label for the progress bar, or nil if no metadata.
    private var epubProgressLabel: String? {
        guard let meta = viewModel.metadata else { return nil }
        return EPUBProgressCalculator.label(
            spineIndex: viewModel.currentSpineIndex,
            totalSpineItems: meta.spineCount
        )
    }

    // MARK: - Navigation

    private var currentChapterTitle: String? {
        guard let meta = viewModel.metadata else { return nil }
        let index = viewModel.currentSpineIndex
        guard index >= 0, index < meta.spineItems.count else { return nil }
        return meta.spineItems[index].title
    }

    private func navigateChapter(offset: Int) {
        let newIndex = viewModel.currentSpineIndex + offset
        viewModel.navigateToSpine(index: newIndex)

        // Clear any previous web view error on navigation
        webViewError = nil
        // Chapter navigation always starts at the top
        seekScrollFraction = nil
        // Issue 6: Reset pagination state so stale page index from previous chapter
        // is not applied to the newly loaded chapter.
        pageNavigator.reset()
        currentPaginationPage = nil

        // Update the WKWebView content URL
        if let meta = viewModel.metadata,
           let base = resourceBase,
           newIndex >= 0, newIndex < meta.spineItems.count {
            let href = meta.spineItems[newIndex].href
            contentURL = base.appendingPathComponent(href)
            // Update progress bar to reflect new chapter position
            readingProgress = EPUBProgressCalculator.progress(
                spineIndex: newIndex,
                scrollFraction: 0.0,
                totalSpineItems: meta.spineCount
            )
        }
    }

    /// Handles seeking from the progress bar scrubber.
    /// Maps the seek value to a spine index and scroll fraction, then navigates there.
    private func handleProgressSeek(_ seekValue: Double) {
        guard let meta = viewModel.metadata,
              let base = resourceBase,
              meta.spineCount > 0 else { return }
        let target = EPUBProgressCalculator.seekTarget(
            seekValue: seekValue,
            totalSpineItems: meta.spineCount
        )
        let targetIndex = target.spineIndex
        guard targetIndex >= 0, targetIndex < meta.spineItems.count else { return }

        viewModel.navigateToSpine(index: targetIndex)
        webViewError = nil

        let href = meta.spineItems[targetIndex].href
        // Apply scrollFraction so EPUBWebViewBridge scrolls within the chapter
        seekScrollFraction = target.scrollFraction
        contentURL = base.appendingPathComponent(href)
        readingProgress = seekValue
    }

    // MARK: - Highlight Actions

    /// Persists a highlight and injects the CSS highlight into the WKWebView.
    /// Phase R4b: delegates to coordinator (which calls renderer for JS injection).
    private func handleHighlightAction(
        event: ReaderSelectionEvent,
        container: ModelContainer
    ) {
        guard let locator = viewModel.makeCurrentLocator() else {
            pendingSelectionEvent = nil
            return
        }

        if let coordinator = highlightCoordinator {
            Task {
                await coordinator.create(
                    locator: locator,
                    anchor: event.anchor,
                    selectedText: event.selectedText,
                    color: "yellow"
                )
            }
        } else {
            // Fallback: direct persistence if coordinator not ready
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                if let record = try? await EPUBHighlightActions.persistHighlight(
                    event: event, locator: locator,
                    persistence: persistence, bookKey: viewModel.bookFingerprintKey
                ), let js = EPUBHighlightActions.createHighlightJS(for: record) {
                    pendingHighlightJS = js
                }
            }
        }
        pendingSelectionEvent = nil
    }

    // MARK: - Note Input Sheet

    @ViewBuilder
    private var noteInputSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let event = pendingSelectionEvent {
                    Text(event.selectedText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                TextEditor(text: $noteText)
                    .frame(minHeight: 100)
                    .padding(.horizontal)
                    .accessibilityIdentifier("epubNoteTextEditor")
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showNoteSheet = false
                        pendingSelectionEvent = nil
                    }
                    .accessibilityIdentifier("epubNoteCancelButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let event = pendingSelectionEvent,
                              let container = modelContainer else {
                            showNoteSheet = false
                            return
                        }
                        handleHighlightWithNote(
                            event: event,
                            container: container,
                            note: noteText.isEmpty ? nil : noteText
                        )
                        showNoteSheet = false
                    }
                    .accessibilityIdentifier("epubNoteSaveButton")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// Persists a highlight with an attached note.
    /// Phase R4b: delegates to coordinator.
    private func handleHighlightWithNote(
        event: ReaderSelectionEvent,
        container: ModelContainer,
        note: String?
    ) {
        guard let locator = viewModel.makeCurrentLocator() else {
            pendingSelectionEvent = nil
            return
        }

        if let coordinator = highlightCoordinator {
            Task {
                await coordinator.create(
                    locator: locator,
                    anchor: event.anchor,
                    selectedText: event.selectedText,
                    color: "yellow",
                    note: note
                )
            }
        } else {
            // Fallback: direct persistence if coordinator not ready
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                if let record = try? await persistence.addHighlight(
                    locator: locator, anchor: event.anchor,
                    selectedText: event.selectedText, color: "yellow",
                    note: note, toBookWithKey: viewModel.bookFingerprintKey
                ), let js = EPUBHighlightActions.createHighlightJS(for: record) {
                    pendingHighlightJS = js
                }
            }
        }
        pendingSelectionEvent = nil
    }

    /// Restores saved highlights for the current chapter after a page finishes loading.
    /// Phase R4b: delegates to coordinator which calls EPUBHighlightRenderer.
    private func restoreHighlightsOnLoad(evaluateJS: @escaping (String) -> Void) {
        guard let href = viewModel.currentPosition?.href else { return }
        highlightRenderer.currentHref = href

        if let coordinator = highlightCoordinator {
            // Temporarily redirect renderer output to the evaluateJS closure
            // for immediate injection (page is ready now).
            let originalCallback = highlightRenderer.onInjectJS
            highlightRenderer.onInjectJS = evaluateJS
            Task {
                await coordinator.restoreAll()
                highlightRenderer.onInjectJS = originalCallback
            }
        } else {
            // Fallback: direct fetch if coordinator not ready
            guard let container = modelContainer else { return }
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                let highlights = (try? await persistence.fetchHighlights(
                    forBookWithKey: viewModel.bookFingerprintKey
                )) ?? []
                let js = EPUBHighlightActions.restoreHighlightsJS(
                    highlights: highlights, currentHref: href
                )
                if !js.isEmpty { evaluateJS(js) }
            }
        }
    }
}
#endif
