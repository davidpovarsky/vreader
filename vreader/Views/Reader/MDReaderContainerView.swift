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
import UIKit

/// Container view for the Markdown reader screen.
struct MDReaderContainerView: View {
    let fileURL: URL
    let viewModel: MDReaderViewModel
    var settingsStore: ReaderSettingsStore?

    @Environment(\.scenePhase) private var scenePhase

    /// Captured scroll position for one-shot restore. Set once after file opens.
    @State private var initialRestoreOffset: Int?

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
        .accessibilityIdentifier("mdReaderContainer")
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
            delegate: viewModel
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("mdReaderContent")
    }
}
#endif
