// Purpose: SwiftUI view that renders one page at a time using NativeTextPageNavigator.
// Used by TXT/MD containers when layout is set to paged mode.
//
// Key decisions:
// - Renders the current page's text in a non-scrollable UITextView.
// - Listens for .readerNextPage/.readerPreviousPage notifications for tap zone navigation.
// - Shows page indicator ("Page X of Y") at the bottom.
// - Supports both plain text and attributed text.
// - Posts .readerPositionDidChange after page changes for AI panel context.
//
// @coordinates-with: NativeTextPageNavigator.swift, TXTReaderContainerView.swift,
//   MDReaderContainerView.swift, TapZoneOverlay.swift, PageTurnAnimator.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Single-page text view for native TXT/MD paged mode.
struct NativeTextPagedView: UIViewRepresentable {
    let navigator: NativeTextPageNavigator
    /// The full plain text (for extracting current page content).
    let fullText: String
    /// The full attributed text (for MD rich formatting). Nil for plain TXT.
    let fullAttributedText: NSAttributedString?
    /// Theme-aware text view configuration.
    let config: TXTViewConfig
    /// Explicit page index so SwiftUI detects page changes and triggers updateUIView.
    let currentPage: Int
    /// Page turn animation style.
    let pageTurnAnimation: PageTurnAnimation

    func makeUIView(context: Context) -> NativePagedContainer {
        let container = NativePagedContainer()
        container.applyConfig(config)
        applyContent(to: container.textView)
        container.accessibilityIdentifier = "nativeTextPagedView"
        return container
    }

    func updateUIView(_ container: NativePagedContainer, context: Context) {
        container.applyConfig(config)

        // Animate page transition if needed
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
        Coordinator()
    }

    // MARK: - Private

    private func applyContent(to textView: UITextView) {
        if let attrText = fullAttributedText,
           let pageAttr = navigator.currentPageAttributedText(from: attrText) {
            textView.attributedText = pageAttr
        } else if let pageText = navigator.currentPageText(from: fullText) {
            textView.text = pageText
        } else {
            textView.text = ""
        }
    }

    final class Coordinator {
        var lastPage: Int = -1
    }
}

/// Container UIView that holds a UITextView and supports page turn animations.
@MainActor
final class NativePagedContainer: UIView {
    let textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    /// Snapshot view used during page turn animations.
    private var snapshotView: UIView?

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

    func applyConfig(_ config: TXTViewConfig) {
        textView.backgroundColor = config.backgroundColor
        textView.textColor = config.textColor
        backgroundColor = config.backgroundColor
    }

    /// Performs page turn animation: snapshots current content, applies new content,
    /// then animates the transition.
    func animatePageChange(
        animation: PageTurnAnimation,
        direction: PageTurnAnimator.Direction,
        applyContent: () -> Void
    ) {
        guard animation != .none else {
            applyContent()
            return
        }

        // Snapshot current state
        let snapshot = textView.snapshotView(afterScreenUpdates: false) ?? UIView()
        snapshot.frame = textView.frame
        addSubview(snapshot)

        // Apply new content
        applyContent()

        // Animate: snapshot is "from", textView is "to"
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
        snapshotView = snapshot
    }
}
#endif
