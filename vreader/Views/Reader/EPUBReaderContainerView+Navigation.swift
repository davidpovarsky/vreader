// Purpose: Bottom overlay, progress bar helpers, chapter navigation, and seek
// handling for EPUBReaderContainerView. Pure code extraction — no logic changes.
//
// @coordinates-with: EPUBReaderContainerView.swift, EPUBProgressCalculator.swift,
//   ReadingProgressBar.swift, EPUBReaderViewModel.swift

#if canImport(UIKit)
import SwiftUI

extension EPUBReaderContainerView {

    @ViewBuilder
    var bottomOverlay: some View {
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
    var epubDiscreteSteps: Int? {
        guard let meta = viewModel.metadata else { return nil }
        return EPUBProgressCalculator.discreteSteps(totalSpineItems: meta.spineCount)
    }

    /// "Chapter X of Y" label for the progress bar, or nil if no metadata.
    var epubProgressLabel: String? {
        guard let meta = viewModel.metadata else { return nil }
        return EPUBProgressCalculator.label(
            spineIndex: viewModel.currentSpineIndex,
            totalSpineItems: meta.spineCount
        )
    }

    // MARK: - Navigation

    var currentChapterTitle: String? {
        guard let meta = viewModel.metadata else { return nil }
        let index = viewModel.currentSpineIndex
        guard index >= 0, index < meta.spineItems.count else { return nil }
        return meta.spineItems[index].title
    }

    func navigateChapter(offset: Int) {
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
    func handleProgressSeek(_ seekValue: Double) {
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
}
#endif
