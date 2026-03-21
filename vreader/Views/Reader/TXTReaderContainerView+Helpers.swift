// Purpose: Notification dependencies, chunked reader content, chunk index lookup,
// no-op coordinator factory, and pagination helpers for TXTReaderContainerView.
// Pure code extraction — no logic changes.
//
// @coordinates-with: TXTReaderContainerView.swift, TXTChunkedReaderBridge.swift,
//   TextReaderUIState.swift, HighlightCoordinator.swift, TextHighlightRenderer.swift,
//   NativeTextPageNavigator.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData

extension TXTReaderContainerView {

    // MARK: - Notification Dependencies

    func makeNotificationDeps() -> ReaderNotificationDeps {
        let container = modelContainer
        return ReaderNotificationDeps(
            bookFingerprintKey: viewModel.bookFingerprintKey,
            bookFingerprint: viewModel.bookFingerprint,
            bookmarkPersistence: container.map { PersistenceActor(modelContainer: $0) } ?? NoOpBookmarkStore(),
            highlightPersistence: container.map { PersistenceActor(modelContainer: $0) } ?? NoOpHighlightStore(),
            annotationPersistence: container.map { PersistenceActor(modelContainer: $0) } ?? NoOpAnnotationStore(),
            locatorFactory: { fp, start, end, text in
                LocatorFactory.txtRange(fingerprint: fp, charRangeStartUTF16: start, charRangeEndUTF16: end, sourceText: text)
            },
            sourceText: { [viewModel] in viewModel.textContent },
            makeCurrentLocator: { [viewModel] in viewModel.makeLocator() },
            onNavigate: { [viewModel] offset in viewModel.updateScrollPosition(charOffsetUTF16: offset) },
            hapticFeedback: HapticFeedbackProvider()
        )
    }

    // MARK: - Chunked Reader Content

    @ViewBuilder
    func chunkedReaderContent(chunks: [String], offsets: [Int]) -> some View {
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
            scrollToOffset: uiState.scrollToOffset,
            highlightRange: uiState.highlightRange,
            highlightIsTemporary: uiState.highlightIsTemporary,
            persistedHighlights: uiState.persistedHighlightRanges
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

    // MARK: - Highlight Coordinator (Phase R4)

    /// Fallback coordinator used before the real one is initialized in .task.
    func makeNoOpCoordinator() -> HighlightCoordinator {
        let renderer = highlightRenderer ?? TextHighlightRenderer(uiState: uiState)
        return HighlightCoordinator(
            renderer: renderer,
            persistence: NoOpHighlightStore(),
            bookFingerprintKey: viewModel.bookFingerprintKey
        )
    }

    // MARK: - Paged Mode Helpers (B08, B10)

    /// Creates or updates the page navigator when entering paged mode.
    func updatePaginationIfNeeded() {
        uiState.updatePagination(
            isPagedMode: isPagedMode,
            attributedText: preparedAttrString,
            initialRestoreOffset: initialRestoreOffset,
            autoPageTurnEnabled: settingsStore?.autoPageTurn ?? false,
            autoPageTurnInterval: settingsStore?.autoPageTurnInterval ?? 5.0
        )
        if let offset = uiState.syncPagedState() {
            viewModel.updateScrollPosition(charOffsetUTF16: offset)
        }
    }
}
#endif
