// Purpose: UIViewRepresentable wrapping a UITextView with TextKit 2 for continuous
// scroll rendering in the unified reflow engine (WI-B04).
//
// Key decisions:
// - Uses UITextView with NSTextLayoutManager (TextKit 2) for text layout.
// - Reports scroll position changes back to ViewModel via delegate pattern.
// - Non-editable, selectable text view for reading.
// - Respects settings (font, theme colors) from ReaderSettingsStore.
// - When attributed text is available, renders it instead of plain text.
//
// @coordinates-with: UnifiedTextRendererViewModel.swift, UnifiedTextRenderer.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Continuous scroll text view using TextKit 2 for the unified reflow engine.
struct UnifiedScrollView: UIViewRepresentable {
    let viewModel: UnifiedTextRendererViewModel

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        applyContent(to: textView)
        textView.delegate = context.coordinator
        textView.accessibilityIdentifier = "unifiedScrollTextView"
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
        if let attrText = viewModel.attributedText {
            textView.attributedText = attrText
        } else {
            textView.text = viewModel.text
            textView.font = .systemFont(ofSize: 17)
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        let viewModel: UnifiedTextRendererViewModel

        init(viewModel: UnifiedTextRendererViewModel) {
            self.viewModel = viewModel
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? UITextView else { return }
            // Calculate character offset from scroll position
            let point = CGPoint(x: 0, y: scrollView.contentOffset.y)
            if let position = textView.closestPosition(to: point) {
                let offset = textView.offset(from: textView.beginningOfDocument, to: position)
                Task { @MainActor in
                    viewModel.updateScrollOffset(charOffsetUTF16: offset)
                }
            }
        }
    }
}
#endif
