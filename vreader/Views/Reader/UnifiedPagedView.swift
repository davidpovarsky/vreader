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
    /// Page turn animation style (B11). Defaults to .none for backward compatibility.
    var pageTurnAnimation: PageTurnAnimation = .none

    func makeUIView(context: Context) -> UnifiedPagedContainer {
        let container = UnifiedPagedContainer()
        applyContent(to: container.textView)
        container.accessibilityIdentifier = "unifiedPagedTextView"

        // Add swipe gestures for page navigation
        let swipeLeft = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSwipeLeft)
        )
        swipeLeft.direction = .left
        container.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSwipeRight)
        )
        swipeRight.direction = .right
        container.addGestureRecognizer(swipeRight)

        return container
    }

    func updateUIView(_ container: UnifiedPagedContainer, context: Context) {
        let oldPage = context.coordinator.lastPage
        if oldPage != currentPage && oldPage >= 0 {
            let direction: PageTurnAnimator.Direction = currentPage > oldPage ? .forward : .backward
            container.animatePageChange(
                animation: pageTurnAnimation,
                direction: direction
            ) {
                self.applyContent(to: container.textView)
            }
        } else {
            applyContent(to: container.textView)
        }
        context.coordinator.lastPage = currentPage
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
        var lastPage: Int = -1

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

/// Container UIView for the unified paged view. Supports page turn animations (B11).
@MainActor
final class UnifiedPagedContainer: UIView {
    let textView: UITextView = {
        let tv = UITextView(usingTextLayoutManager: true)
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.font = .systemFont(ofSize: 17)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func animatePageChange(
        animation: PageTurnAnimation,
        direction: PageTurnAnimator.Direction,
        applyContent: () -> Void
    ) {
        guard animation != .none else {
            applyContent()
            return
        }

        let snapshot = textView.snapshotView(afterScreenUpdates: false) ?? UIView()
        snapshot.frame = textView.frame
        addSubview(snapshot)

        applyContent()

        PageTurnAnimator.transition(
            from: snapshot,
            to: textView,
            animation: animation,
            direction: direction
        ) {
            Task { @MainActor in
                snapshot.removeFromSuperview()
            }
        }
    }
}
#endif
