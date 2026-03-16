// Purpose: UIViewRepresentable that renders one page at a time using TextKit2Paginator
// for the unified reflow engine (WI-B04).
//
// Key decisions:
// - Renders the current page's text in a non-scrollable UITextView.
// - Swipe left/right triggers page navigation via the ViewModel.
// - Text container sized to viewport for accurate per-page rendering.
// - Integrates with PageNavigator protocol for consistent navigation.
//
// @coordinates-with: UnifiedTextRendererViewModel.swift, UnifiedTextRenderer.swift,
//   TextKit2Paginator.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Single-page text view for paged mode in the unified reflow engine.
struct UnifiedPagedView: UIViewRepresentable {
    let viewModel: UnifiedTextRendererViewModel

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.font = .systemFont(ofSize: 17)
        textView.text = viewModel.currentPageText ?? ""
        textView.accessibilityIdentifier = "unifiedPagedTextView"

        // Add swipe gestures for page navigation
        let swipeLeft = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSwipeLeft)
        )
        swipeLeft.direction = .left
        textView.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSwipeRight)
        )
        swipeRight.direction = .right
        textView.addGestureRecognizer(swipeRight)

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.text = viewModel.currentPageText ?? ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    @MainActor
    class Coordinator: NSObject {
        let viewModel: UnifiedTextRendererViewModel

        init(viewModel: UnifiedTextRendererViewModel) {
            self.viewModel = viewModel
        }

        @objc func handleSwipeLeft() {
            viewModel.nextPage()
        }

        @objc func handleSwipeRight() {
            viewModel.previousPage()
        }
    }
}
#endif
