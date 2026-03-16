// Purpose: SwiftUI view that renders text using TextKit 2 in either scroll or paged mode.
// Entry point for the unified TXT reflow engine (WI-B04).
// Dispatches to UnifiedScrollView or UnifiedPagedView based on layout preference.
//
// Key decisions:
// - Owns UnifiedTextRendererViewModel lifecycle.
// - Reads text from file URL on appear.
// - Delegates to UnifiedScrollView (scroll mode) or UnifiedPagedView (paged mode).
// - Integrates with ReadingProgressBar for seek/scrub.
// - Posts .readerPositionDidChange notifications for AI panel context.
//
// @coordinates-with: UnifiedTextRendererViewModel.swift, UnifiedPagedView.swift,
//   UnifiedScrollView.swift, ReaderContainerView.swift

#if canImport(UIKit)
import SwiftUI

/// Unified text renderer for TXT files — supports scroll and paged modes.
struct UnifiedTextRenderer: View {
    let text: String
    let settingsStore: ReaderSettingsStore
    @Binding var readingProgress: Double
    var onProgressChange: ((Double) -> Void)?

    @State private var viewModel: UnifiedTextRendererViewModel?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let vm = viewModel {
                    if vm.isPagedMode {
                        UnifiedPagedView(viewModel: vm)
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
        vm.configure(
            font: settingsStore.uiFont,
            viewportSize: viewportSize,
            layout: settingsStore.epubLayout
        )
        viewModel = vm
    }

    private func reconfigure(viewportSize: CGSize) {
        viewModel?.configure(
            font: settingsStore.uiFont,
            viewportSize: viewportSize,
            layout: settingsStore.epubLayout
        )
    }
}
#endif
