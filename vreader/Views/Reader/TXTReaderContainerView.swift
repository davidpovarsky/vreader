// Purpose: SwiftUI container for the TXT reader. Composes the TXTTextViewBridge
// (small files) or TXTChunkedReaderBridge (large files) with loading/error overlays.
//
// Key decisions:
// - Owns TXTReaderViewModel lifecycle (open on appear, close on disappear).
// - Delegates scroll/selection events from bridge to ViewModel.
// - Shows loading spinner during file open.
// - Shows error message on failure.
// - Passes theme config to bridge (font size, line spacing).
// - Builds NSAttributedString on a background thread to avoid blocking the main
//   thread for large files. The bridge receives the pre-built attributed string.
// - Files over `largeFileThreshold` UTF-16 code units use chunked rendering
//   (UITableView) to avoid TextKit 1 glyph storage blowup.
//
// @coordinates-with: TXTReaderViewModel.swift, TXTTextViewBridge.swift,
//   TXTChunkedReaderBridge.swift, TXTTextChunker.swift, TXTAttributedStringBuilder.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Container view for the TXT reader screen.
struct TXTReaderContainerView: View {
    let fileURL: URL
    let viewModel: TXTReaderViewModel
    var settingsStore: ReaderSettingsStore?

    @Environment(\.scenePhase) private var scenePhase

    /// Files with more UTF-16 code units than this use chunked rendering.
    static let largeFileThreshold = 500_000

    /// Pre-built attributed string for small files, constructed off the main thread.
    @State private var preparedAttrString: NSAttributedString?
    /// True while the attributed string is being built in the background.
    @State private var isBuildingAttrString = false
    /// Pre-split chunks for large files.
    @State private var textChunks: [String]?
    /// Cumulative UTF-16 start offsets per chunk.
    @State private var chunkStartOffsets: [Int]?
    /// Captured scroll position for one-shot restore. Set once after file opens.
    /// Using @State breaks the observation cycle that caused bug #15/#17:
    /// reading viewModel.currentOffsetUTF16 in body created a feedback loop.
    @State private var initialRestoreOffset: Int?

    /// Whether the loaded text exceeds the large file threshold.
    private var isLargeFile: Bool {
        viewModel.totalTextLengthUTF16 > Self.largeFileThreshold
    }

    /// Composite key that triggers attributed string rebuild when text or config changes.
    /// Uses totalTextLengthUTF16 + totalWordCount (O(1)) instead of text.hashValue (O(n)).
    private var attrStringKey: String {
        let hasText = viewModel.textContent != nil
        let len = viewModel.totalTextLengthUTF16
        let words = viewModel.totalWordCount
        let cfg = settingsStore?.txtViewConfig ?? TXTViewConfig()
        return "\(hasText)-\(len)-\(words)-\(cfg.fontSize)-\(cfg.fontName ?? "sys")-\(cfg.lineSpacing)-\(cfg.letterSpacing)"
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading || isBuildingAttrString {
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
                // Small file → single UITextView
                readerContent(text: text, attributedText: attrStr)
            } else if viewModel.textContent != nil {
                loadingView
            } else {
                Color.clear
            }
        }
        .task {
            await viewModel.open(url: fileURL)
            // Capture restored position once — do NOT read currentOffsetUTF16
            // in body, as it changes on every scroll and creates a feedback loop.
            initialRestoreOffset = viewModel.currentOffsetUTF16
        }
        .task(id: attrStringKey) {
            guard let text = viewModel.textContent else { return }
            let config = settingsStore?.txtViewConfig ?? TXTViewConfig()

            if text.utf16.count > Self.largeFileThreshold {
                // Large file: split into chunks (fast, no attributed string needed here)
                isBuildingAttrString = true
                defer { isBuildingAttrString = false }

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
                isBuildingAttrString = true
                defer { isBuildingAttrString = false }

                let wrapped = await Task.detached(priority: .userInitiated) {
                    TXTAttributedStringBuilder.buildSendable(text: text, config: config)
                }.value
                guard !Task.isCancelled else { return }
                preparedAttrString = wrapped.value
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
    private func readerContent(text: String, attributedText: NSAttributedString) -> some View {
        TXTTextViewBridge(
            text: text,
            attributedText: attributedText,
            config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
            restoreOffset: initialRestoreOffset,
            delegate: viewModel
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("txtReaderContent")
    }

    @ViewBuilder
    private func chunkedReaderContent(chunks: [String], offsets: [Int]) -> some View {
        let chunkIdx = Self.chunkIndex(for: initialRestoreOffset ?? 0, in: offsets)
        let intraFraction: CGFloat? = {
            guard let idx = chunkIdx, let offset = initialRestoreOffset else { return nil }
            let chunkStart = offsets[idx]
            let nextStart = idx + 1 < offsets.count ? offsets[idx + 1] : viewModel.totalTextLengthUTF16
            let chunkLen = nextStart - chunkStart
            guard chunkLen > 0 else { return nil }
            return CGFloat(offset - chunkStart) / CGFloat(chunkLen)
        }()

        TXTChunkedReaderBridge(
            chunks: chunks,
            config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
            restoreChunkIndex: chunkIdx,
            restoreIntraChunkOffset: intraFraction,
            delegate: viewModel,
            chunkStartOffsets: offsets
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("txtReaderChunkedContent")
    }

    /// Finds the chunk index containing the given character offset.
    static func chunkIndex(for charOffset: Int, in offsets: [Int]) -> Int? {
        guard charOffset > 0, !offsets.isEmpty else { return nil }
        var lo = 0, hi = offsets.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if offsets[mid] <= charOffset {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }
}
#endif
