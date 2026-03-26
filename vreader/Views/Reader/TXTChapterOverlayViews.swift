// Purpose: Chapter-specific overlay views for TXTReaderContainerView (WI-6).
// Extracted to keep the container view under ~300 lines.
//
// Key decisions:
// - Chapter title overlay at top of screen, only shown when chrome is visible.
// - Chapter bottom overlay combines prev/next navigation buttons with progress bar.
// - Uses ChapterProgressCalculator for book-level progress computation.
// - Clears chapterAttrString before navigation to trigger rebuild via .task(id:).
//
// @coordinates-with: TXTReaderContainerView.swift, TXTReaderViewModel.swift,
//   ChapterProgressCalculator.swift, ReaderBottomOverlay.swift

#if canImport(UIKit)
import SwiftUI

// MARK: - Chapter Title Overlay

/// Small overlay showing the current chapter title at the top of the reader screen.
struct ChapterTitleOverlay: View {
    let title: String
    let settingsStore: ReaderSettingsStore?

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(backgroundColor.opacity(0.92))
            .accessibilityIdentifier("txtChapterTitleOverlay")
    }

    private var backgroundColor: Color {
        Color(settingsStore?.theme.backgroundColor ?? ReaderTheme.default.backgroundColor)
    }
}

// MARK: - Chapter Bottom Overlay

/// Bottom overlay for chapter-based display: prev/next buttons + book-level progress.
struct ChapterBottomOverlay: View {
    let viewModel: TXTReaderViewModel
    let bookProgress: Double?
    let settingsStore: ReaderSettingsStore?
    /// Binding to clear the attributed string cache when navigating.
    var onNavigate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Chapter navigation buttons
            HStack {
                Button {
                    onNavigate()
                    viewModel.goToPreviousChapter()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption2)
                        Text("Previous")
                            .font(.caption)
                    }
                }
                .disabled(!viewModel.hasPreviousChapter)
                .accessibilityIdentifier("txtChapterPrevButton")

                Spacer()

                Text("\(viewModel.currentChapterIdx + 1) / \(viewModel.totalChapterCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("txtChapterIndicator")

                Spacer()

                Button {
                    onNavigate()
                    viewModel.goToNextChapter()
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                }
                .disabled(!viewModel.hasNextChapter)
                .accessibilityIdentifier("txtChapterNextButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            // Chapter-level progress (book position shown by chapter indicator above)
            ReaderBottomOverlay(
                progress: bookProgress,
                sessionTime: viewModel.sessionTimeDisplay,
                settingsStore: settingsStore,
                accessibilityPrefix: "txt"
            )
        }
        .accessibilityIdentifier("txtChapterBottomOverlay")
    }
}
#endif
