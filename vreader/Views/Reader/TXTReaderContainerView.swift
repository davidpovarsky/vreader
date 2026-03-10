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
import SwiftData
import UIKit

/// Container view for the TXT reader screen.
struct TXTReaderContainerView: View {
    let fileURL: URL
    let viewModel: TXTReaderViewModel
    var settingsStore: ReaderSettingsStore?
    var modelContainer: ModelContainer?

    @Environment(\.scenePhase) private var scenePhase
    /// Mirrors ReaderContainerView's chrome toggle so the bottom overlay hides with the nav bar.
    @State private var isChromeVisible = true

    /// Files with more UTF-16 code units than this use chunked rendering.
    static let largeFileThreshold = 500_000

    /// Pre-built attributed string for small files, constructed off the main thread.
    @State private var preparedAttrString: NSAttributedString?
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
    @State private var initialRestoreOffset: Int?
    /// Navigation target from search results. Updated via notification.
    @State private var scrollToOffset: Int?
    /// Match highlight range for search navigation (bug #43).
    @State private var highlightRange: NSRange?
    /// Whether the current highlight is temporary (search nav) or persistent (user-created).
    /// Temporary highlights auto-clear after 3s; persistent ones survive cell reuse (bug #54).
    @State private var highlightIsTemporary: Bool = true
    /// Pending annotation info for the "Add Note" flow (bug #44).
    @State private var pendingAnnotationInfo: TextSelectionInfo?
    /// Text input for the annotation note.
    @State private var annotationNoteText: String = ""
    /// Persisted highlight ranges loaded from DB on file open (bug #55).
    @State private var persistedHighlightRanges: [NSRange] = []

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
                // Small file → single UITextView
                readerContent(text: text, attributedText: attrStr)
            } else if viewModel.textContent != nil {
                loadingView
            } else {
                Color.clear
            }

            // Bottom overlay for session time and progress (bug #33)
            if viewModel.textContent != nil && !viewModel.isLoading && isChromeVisible {
                VStack {
                    Spacer()
                    txtBottomOverlay
                }
            }
        }
        .task {
            await viewModel.open(url: fileURL)
            // Capture restored position once — do NOT read currentOffsetUTF16
            // in body, as it changes on every scroll and creates a feedback loop.
            initialRestoreOffset = viewModel.currentOffsetUTF16
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
            guard let locator = notification.object as? Locator else { return }
            // Derive scroll offset: prefer charOffsetUTF16, fall back to charRangeStartUTF16 (bug #50)
            guard let offset = locator.charOffsetUTF16 ?? locator.charRangeStartUTF16 else { return }
            scrollToOffset = offset
            // Set highlight range for search match visualization (bug #43)
            // Search highlights are temporary — auto-clear after 3s
            highlightIsTemporary = true
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
            guard let locator = LocatorFactory.txtRange(
                fingerprint: viewModel.bookFingerprint,
                charRangeStartUTF16: info.startUTF16,
                charRangeEndUTF16: info.endUTF16,
                sourceText: viewModel.textContent
            ) else { return }
            // Apply persistent visual highlight feedback (bug #46, #54)
            // User-created highlights don't auto-clear — they persist until replaced
            highlightIsTemporary = false
            let newRange = NSRange(location: info.startUTF16, length: info.endUTF16 - info.startUTF16)
            highlightRange = newRange
            // Add to persisted highlights so it survives text rebuilds (bug #55)
            persistedHighlightRanges.append(newRange)
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
        .sheet(isPresented: .init(
            get: { pendingAnnotationInfo != nil },
            set: { if !$0 { pendingAnnotationInfo = nil } }
        )) {
            AddNoteSheet(
                selectedText: pendingAnnotationInfo?.selectedText ?? "",
                noteText: $annotationNoteText,
                onSave: {
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
                    guard let locator = LocatorFactory.txtRange(
                        fingerprint: viewModel.bookFingerprint,
                        charRangeStartUTF16: info.startUTF16,
                        charRangeEndUTF16: info.endUTF16,
                        sourceText: viewModel.textContent
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
                },
                onCancel: {
                    pendingAnnotationInfo = nil
                }
            )
            .presentationDetents([.medium])
        }
        .accessibilityIdentifier("txtReaderContainer")
        .accessibilityValue(initialRestoreOffset.map { "restoredOffset:\($0)" } ?? "restoredOffset:none")
    }

    // MARK: - Bottom Overlay

    private var overlaySecondaryColor: Color {
        Color(settingsStore?.theme.secondaryTextColor ?? ReaderTheme.default.secondaryTextColor)
    }

    private var overlayBackground: Color {
        Color(settingsStore?.theme.backgroundColor ?? ReaderTheme.default.backgroundColor).opacity(0.92)
    }

    @ViewBuilder
    private var txtBottomOverlay: some View {
        HStack {
            if let progress = viewModel.totalProgression {
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(overlaySecondaryColor)
                    .accessibilityLabel("Reading progress \(Int(progress * 100)) percent")
                    .accessibilityIdentifier("txtProgressIndicator")
            }

            Spacer()

            if let sessionTime = viewModel.sessionTimeDisplay {
                Text(sessionTime)
                    .font(.caption)
                    .foregroundColor(overlaySecondaryColor)
                    .accessibilityIdentifier("txtSessionTime")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(overlayBackground)
        .accessibilityIdentifier("txtBottomOverlay")
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
            scrollToOffset: scrollToOffset,
            highlightRange: highlightRange,
            highlightIsTemporary: highlightIsTemporary,
            persistedHighlights: persistedHighlightRanges,
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
            chunkStartOffsets: offsets,
            scrollToOffset: scrollToOffset,
            highlightRange: highlightRange,
            highlightIsTemporary: highlightIsTemporary,
            persistedHighlights: persistedHighlightRanges
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
