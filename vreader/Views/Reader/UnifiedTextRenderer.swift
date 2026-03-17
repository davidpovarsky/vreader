// Purpose: SwiftUI view that renders text using TextKit 2 in either scroll or paged mode.
// Entry point for the unified reflow engine (WI-B04, WI-B05, WI-B07).
// Dispatches to UnifiedScrollView or UnifiedPagedView based on layout preference.
// Supports both plain text (TXT) and attributed text (MD, simple EPUB chapters).
//
// Key decisions:
// - Owns UnifiedTextRendererViewModel lifecycle.
// - Reads text from file URL on appear.
// - Delegates to UnifiedScrollView (scroll mode) or UnifiedPagedView (paged mode).
// - Integrates with ReadingProgressBar for seek/scrub.
// - Posts .readerPositionDidChange notifications for AI panel context.
// - When `attributedText` is provided, uses configureAttributed() to preserve formatting.
//
// @coordinates-with: UnifiedTextRendererViewModel.swift, UnifiedPagedView.swift,
//   UnifiedScrollView.swift, ReaderContainerView.swift, EPUBTextStripper.swift

#if canImport(UIKit)
import SwiftUI

/// Unified text renderer — supports scroll and paged modes with plain or attributed text.
struct UnifiedTextRenderer: View {
    let text: String
    let settingsStore: ReaderSettingsStore
    @Binding var readingProgress: Double
    var onProgressChange: ((Double) -> Void)?
    /// Optional attributed text for rich formatting (MD, EPUB). When provided,
    /// the renderer uses `configureAttributed()` to preserve bold, italic, headings.
    var attributedText: NSAttributedString?

    @State private var viewModel: UnifiedTextRendererViewModel?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let vm = viewModel {
                    if vm.isPagedMode {
                        UnifiedPagedView(
                            viewModel: vm,
                            currentPage: vm.currentPage,
                            pageText: vm.currentPageText,
                            pageAttributedText: vm.currentPageAttributedText
                        )
                    } else {
                        UnifiedScrollView(viewModel: vm)
                    }
                } else {
                    ProgressView()
                }
            }
            .onAppear {
                setupViewModel(viewportSize: geometry.size)
            }
            .onChange(of: settingsStore.typography.fontSize) { _, _ in
                reconfigure(viewportSize: geometry.size)
            }
            .onChange(of: settingsStore.epubLayout) { _, _ in
                reconfigure(viewportSize: geometry.size)
            }
        }
        .accessibilityIdentifier("unifiedTextRenderer")
    }

    private func setupViewModel(viewportSize: CGSize) {
        let vm = UnifiedTextRendererViewModel(text: text)
        // Wire progress callback: update binding and post notification
        vm.onProgressChange = { [weak vm] progress in
            readingProgress = progress
            onProgressChange?(progress)
            // Post position change notification for AI panel context
            guard let vm else { return }
            let offset = vm.isPagedMode
                ? vm.charOffsetForProgress(progress)
                : vm.charOffsetForProgress(progress)
            NotificationCenter.default.post(
                name: .readerPositionDidChange,
                object: nil,
                userInfo: ["charOffsetUTF16": offset, "progress": progress]
            )
        }
        if let attrText = attributedText {
            vm.configureAttributed(
                attributedText: attrText,
                viewportSize: viewportSize,
                layout: settingsStore.epubLayout
            )
        } else {
            vm.configure(
                font: settingsStore.uiFont,
                viewportSize: viewportSize,
                layout: settingsStore.epubLayout
            )
        }
        viewModel = vm
    }

    private func reconfigure(viewportSize: CGSize) {
        if let attrText = attributedText {
            viewModel?.configureAttributed(
                attributedText: attrText,
                viewportSize: viewportSize,
                layout: settingsStore.epubLayout
            )
        } else {
            viewModel?.configure(
                font: settingsStore.uiFont,
                viewportSize: viewportSize,
                layout: settingsStore.epubLayout
            )
        }
    }
}
#endif
