// Purpose: SwiftUI container for the Markdown reader. Composes the TXTTextViewBridge
// (with NSAttributedString) with loading/error overlays and reading session chrome.
//
// Key decisions:
// - Owns MDReaderViewModel lifecycle (open on appear, close on disappear).
// - Delegates scroll/selection events from bridge to ViewModel for position persistence.
// - Shows loading spinner during file open.
// - Shows error message on failure.
// - Passes rendered NSAttributedString to bridge for rich display.
//
// @coordinates-with: MDReaderViewModel.swift, TXTTextViewBridge.swift

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
    /// Pending annotation info for the "Add Note" flow (bug #44).
    @State private var pendingAnnotationInfo: TextSelectionInfo?
    /// Text input for the annotation note.
    @State private var annotationNoteText: String = ""

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage, viewModel.renderedText == nil {
                errorView(message: errorMessage)
            } else if let attrStr = viewModel.renderedAttributedString {
                readerContent(attributedString: attrStr)
            } else {
                // Not yet opened
                Color.clear
            }

            // Bottom overlay for progress and session time
            if viewModel.renderedText != nil && !viewModel.isLoading && isChromeVisible {
                VStack {
                    Spacer()
                    mdBottomOverlay
                }
            }
        }
        .task {
            await viewModel.open(url: fileURL)
            initialRestoreOffset = viewModel.currentOffsetUTF16
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
        .onReceive(NotificationCenter.default.publisher(for: .readerBookmarkRequested)) { _ in
            guard let container = modelContainer else { return }
            let persistence = PersistenceActor(modelContainer: container)
            let locator = viewModel.makeLocator()
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
                  let offset = locator.charOffsetUTF16 else { return }
            scrollToOffset = offset
            // Set highlight range for search match visualization (bug #43)
            if let start = locator.charRangeStartUTF16,
               let end = locator.charRangeEndUTF16, end > start {
                highlightRange = NSRange(location: start, length: end - start)
            } else {
                highlightRange = nil
            }
            viewModel.updateScrollPosition(charOffsetUTF16: offset)
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerHighlightRequested)) { notification in
            guard let info = notification.object as? TextSelectionInfo,
                  let container = modelContainer else { return }
            let persistence = PersistenceActor(modelContainer: container)
            guard let locator = LocatorFactory.mdRange(
                fingerprint: viewModel.bookFingerprint,
                charRangeStartUTF16: info.startUTF16,
                charRangeEndUTF16: info.endUTF16,
                sourceText: viewModel.renderedText
            ) else { return }
            Task {
                try? await persistence.addHighlight(
                    locator: locator,
                    selectedText: info.selectedText,
                    color: "yellow",
                    note: nil,
                    toBookWithKey: viewModel.bookFingerprintKey
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerAnnotationRequested)) { notification in
            guard let info = notification.object as? TextSelectionInfo else { return }
            pendingAnnotationInfo = info
            annotationNoteText = ""
        }
        .alert("Add Note", isPresented: .init(
            get: { pendingAnnotationInfo != nil },
            set: { if !$0 { pendingAnnotationInfo = nil } }
        )) {
            TextField("Note", text: $annotationNoteText)
            Button("Save") {
                guard let info = pendingAnnotationInfo,
                      let container = modelContainer else {
                    pendingAnnotationInfo = nil
                    return
                }
                let trimmed = annotationNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    pendingAnnotationInfo = nil
                    return
                }
                let persistence = PersistenceActor(modelContainer: container)
                guard let locator = LocatorFactory.mdRange(
                    fingerprint: viewModel.bookFingerprint,
                    charRangeStartUTF16: info.startUTF16,
                    charRangeEndUTF16: info.endUTF16,
                    sourceText: viewModel.renderedText
                ) else {
                    pendingAnnotationInfo = nil
                    return
                }
                Task {
                    try? await persistence.addAnnotation(
                        locator: locator,
                        content: trimmed,
                        toBookWithKey: viewModel.bookFingerprintKey
                    )
                }
                pendingAnnotationInfo = nil
            }
            Button("Cancel", role: .cancel) {
                pendingAnnotationInfo = nil
            }
        } message: {
            if let info = pendingAnnotationInfo {
                Text("\"\(info.selectedText.prefix(50))\"")
            }
        }
        .accessibilityIdentifier("mdReaderContainer")
    }

    // MARK: - Bottom Overlay

    private var overlaySecondaryColor: Color {
        Color(settingsStore?.theme.secondaryTextColor ?? ReaderTheme.default.secondaryTextColor)
    }

    private var overlayBackground: Color {
        Color(settingsStore?.theme.backgroundColor ?? ReaderTheme.default.backgroundColor).opacity(0.92)
    }

    @ViewBuilder
    private var mdBottomOverlay: some View {
        HStack {
            if let progress = viewModel.totalProgression {
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(overlaySecondaryColor)
                    .accessibilityLabel("Reading progress \(Int(progress * 100)) percent")
                    .accessibilityIdentifier("mdProgressIndicator")
            }

            Spacer()

            if let sessionTime = viewModel.sessionTimeDisplay {
                Text(sessionTime)
                    .font(.caption)
                    .foregroundColor(overlaySecondaryColor)
                    .accessibilityIdentifier("mdSessionTime")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(overlayBackground)
        .accessibilityIdentifier("mdBottomOverlay")
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
    private func readerContent(attributedString: NSAttributedString) -> some View {
        TXTTextViewBridge(
            text: attributedString.string,
            attributedText: attributedString,
            config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
            restoreOffset: initialRestoreOffset,
            scrollToOffset: scrollToOffset,
            highlightRange: highlightRange,
            delegate: viewModel
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("mdReaderContent")
    }
}
#endif
