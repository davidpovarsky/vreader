// Purpose: SwiftUI container for the EPUB reader. Composes the EPUBWebViewBridge
// with loading/error overlays, chapter navigation, and reading session chrome.
//
// Key decisions:
// - Owns EPUBReaderViewModel lifecycle (open on appear, close on disappear).
// - Fetches resourceBaseURL from parser for content URL resolution (hrefs relative to opfDir).
// - Fetches extractedRootURL from parser for WKWebView allowingReadAccessTo (wider access).
// - Bottom overlay shows chapter progress and navigation controls.
// - Scroll progress from WKWebView feeds back to ViewModel.updatePosition.
// - WKWebView load errors surfaced via webViewError state.
//
// @coordinates-with: EPUBReaderViewModel.swift, EPUBWebViewBridge.swift,
//   EPUBParserProtocol.swift

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

            // Bottom navigation overlay
            if viewModel.metadata != nil, !viewModel.isLoading, isChromeVisible {
                VStack {
                    Spacer()
                    bottomOverlay
                }
            }
        }
        .task {
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
        .onReceive(NotificationCenter.default.publisher(for: .readerNavigateToLocator)) { notification in
            guard let locator = notification.object as? Locator,
                  let href = locator.href,
                  let meta = viewModel.metadata,
                  let base = resourceBase else { return }
            if let spineIndex = meta.spineItems.firstIndex(where: { $0.href == href }) {
                viewModel.navigateToSpine(index: spineIndex)
                webViewError = nil
                contentURL = base.appendingPathComponent(href)
            }
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
            onProgressChange: { progress in
                guard let position = viewModel.currentPosition,
                      let metadata = viewModel.metadata else { return }
                let spineIndex = metadata.spineItems.firstIndex(
                    where: { $0.href == position.href }
                ) ?? 0
                let totalProg = metadata.spineCount > 1
                    ? (Double(spineIndex) + progress) / Double(metadata.spineCount)
                    : progress
                let newPosition = EPUBPosition(
                    href: position.href,
                    progression: progress,
                    totalProgression: totalProg,
                    cfi: nil
                )
                viewModel.updatePosition(newPosition)
            },
            onLoadError: { error in
                webViewError = error
            }
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("epubReaderContent")
    }

    @ViewBuilder
    private var bottomOverlay: some View {
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

            VStack(spacing: 2) {
                if let meta = viewModel.metadata {
                    let current = viewModel.currentSpineIndex + 1
                    Text("\(current) of \(meta.spineCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .accessibilityLabel(
                            "Chapter \(current) of \(meta.spineCount)"
                        )
                        .accessibilityIdentifier("epubChapterIndicator")
                }
                if let title = currentChapterTitle {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        .background(Color(settingsStore?.theme.backgroundColor ?? ReaderTheme.default.backgroundColor).opacity(0.92))
        .accessibilityIdentifier("epubBottomOverlay")
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

        // Update the WKWebView content URL
        if let meta = viewModel.metadata,
           let base = resourceBase,
           newIndex >= 0, newIndex < meta.spineItems.count {
            let href = meta.spineItems[newIndex].href
            contentURL = base.appendingPathComponent(href)
        }
    }
}
#endif
