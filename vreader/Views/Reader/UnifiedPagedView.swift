// Purpose: UIViewRepresentable that renders one page at a time using TextKit2Paginator
// for the unified reflow engine (WI-B04).
//
// Key decisions:
// - Renders the current page's text in a non-scrollable UITextView.
// - Swipe left/right triggers page navigation via the ViewModel.
// - Text container sized to viewport for accurate per-page rendering.
// - Integrates with PageNavigator protocol for consistent navigation.
// - Uses attributed text when available (MD/EPUB) for rich formatting.
// - Passes currentPage and currentPageText as explicit properties so SwiftUI
//   detects changes and calls updateUIView on page navigation.
// - Posts .readerPositionDidChange after page changes for AI panel context.
//
// @coordinates-with: UnifiedTextRendererViewModel.swift, UnifiedTextRenderer.swift,
//   TextKit2Paginator.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Single-page text view for paged mode in the unified reflow engine.
struct UnifiedPagedView: UIViewRepresentable {
    let viewModel: UnifiedTextRendererViewModel
    /// Explicit page index so SwiftUI detects page changes and triggers updateUIView.
    let currentPage: Int
    /// Plain text for the current page (triggers SwiftUI diff).
    let pageText: String?
    /// Attributed text for the current page (rich formatting from MD/EPUB).
    let pageAttributedText: NSAttributedString?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.font = .systemFont(ofSize: 17)
        applyContent(to: textView)
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
        applyContent(to: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Private

    /// Applies attributed or plain text to the text view.
    private func applyContent(to textView: UITextView) {
        if let attrText = pageAttributedText {
            textView.attributedText = attrText
        } else {
            textView.text = pageText ?? ""
        }
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
