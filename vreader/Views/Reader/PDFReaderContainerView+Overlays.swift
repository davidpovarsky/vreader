// Purpose: Password, loading, error overlays, progress bar, and bottom overlay
// for PDFReaderContainerView. Pure code extraction — no logic changes.
//
// @coordinates-with: PDFReaderContainerView.swift, PDFPasswordPromptView.swift,
//   ReadingProgressBar.swift, PDFProgressHelper.swift, PDFReaderViewModel.swift

#if canImport(UIKit)
import SwiftUI

extension PDFReaderContainerView {

    // MARK: - Overlays

    @ViewBuilder
    var passwordOverlay: some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
        PDFPasswordPromptView(
            password: $password,
            errorMessage: viewModel.errorMessage,
            onSubmit: {
                passwordAttemptId += 1
                submittedPassword = password
            },
            onCancel: {
                dismiss()
            }
        )
    }

    @ViewBuilder
    var loadingOverlay: some View {
        Color(.systemBackground).opacity(0.9)
            .ignoresSafeArea()
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("pdfReaderLoading")
    }

    func errorOverlay(message: String) -> some View {
        ZStack {
            Color(.systemBackground).opacity(0.9)
                .ignoresSafeArea()
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
            .accessibilityIdentifier("pdfReaderError")
        }
    }

    @ViewBuilder
    var progressBar: some View {
        ReadingProgressBar(
            progress: $readingProgress,
            onSeek: { seekValue in
                let targetPage = PDFProgressHelper.pageForSeekValue(
                    seekValue: seekValue, totalPages: viewModel.totalPages
                )
                restoredPage = targetPage
                viewModel.pageDidChange(to: targetPage)
            },
            discreteSteps: PDFProgressHelper.discreteSteps(totalPages: viewModel.totalPages),
            isVisible: PDFProgressHelper.shouldShowProgressBar(
                isDocumentLoaded: viewModel.isDocumentLoaded,
                totalPages: viewModel.totalPages
            ),
            label: PDFProgressHelper.pageLabel(
                currentPageIndex: viewModel.currentPageIndex,
                totalPages: viewModel.totalPages
            )
        )
        .accessibilityIdentifier("pdfReadingProgressBar")
    }

    @ViewBuilder
    var bottomOverlay: some View {
        HStack {
            Text(viewModel.pageIndicator)
                .font(.caption)
                .monospacedDigit()
                .accessibilityLabel("Page \(viewModel.currentPageIndex + 1) of \(viewModel.totalPages)")
                .accessibilityIdentifier("pdfPageIndicator")

            Spacer()

            if let sessionTime = viewModel.sessionTimeDisplay {
                Text(sessionTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pdfSessionTime")
            }

            if let pph = viewModel.pagesPerHour {
                Text("~\(Int(pph.rounded())) pages/hr")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pdfPagesPerHour")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .accessibilityIdentifier("pdfBottomOverlay")
    }
}
#endif
