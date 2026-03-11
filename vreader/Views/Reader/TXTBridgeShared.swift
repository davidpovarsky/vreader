// Purpose: Shared functions for TXTTextViewBridge and TXTChunkedReaderBridge coordinators.
// Extracted from both bridge coordinators (WI-002) — zero logic change.
//
// Key decisions:
// - postSelectionNotification unifies single-TV and chunked versions via optional chunkOffset.
// - buildReaderEditMenu builds the shared Highlight + Add Note menu for both bridges.
// - postContentTappedNotification extracts the identical tap handler body.
// - gestureRecognizerShouldRecognizeSimultaneously extracts the identical delegate answer.
//
// @coordinates-with TXTTextViewBridge.swift, TXTChunkedReaderBridge.swift,
//   ReaderNotifications.swift

import UIKit

/// Shared utility functions for TXT/MD reader bridge coordinators.
enum TXTBridgeShared {

    /// Posts a selection notification with text and UTF-16 range.
    /// For chunked readers, pass `chunkOffset` to convert chunk-local to document-global.
    @MainActor
    static func postSelectionNotification(
        _ name: Notification.Name,
        from textView: UITextView,
        range: NSRange,
        chunkOffset: Int = 0
    ) {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0 else { return }
        let text = textView.text ?? ""
        let nsText = text as NSString
        guard range.location <= nsText.length,
              range.length <= nsText.length - range.location else { return }
        let selectedText = nsText.substring(with: range)
        let info = TextSelectionInfo(
            selectedText: selectedText,
            startUTF16: chunkOffset + range.location,
            endUTF16: chunkOffset + range.location + range.length
        )
        NotificationCenter.default.post(name: name, object: info)
    }

    /// Builds the shared edit menu with Highlight and Add Note actions.
    @MainActor
    static func buildReaderEditMenu(
        range: NSRange,
        textView: UITextView,
        suggestedActions: [UIMenuElement],
        chunkOffset: Int = 0
    ) -> UIMenu? {
        guard range.length > 0 else { return UIMenu(children: suggestedActions) }

        let highlightAction = UIAction(
            title: "Highlight",
            image: UIImage(systemName: "highlighter")
        ) { [weak textView] _ in
            guard let textView else { return }
            postSelectionNotification(
                .readerHighlightRequested, from: textView, range: range, chunkOffset: chunkOffset
            )
        }

        let noteAction = UIAction(
            title: "Add Note",
            image: UIImage(systemName: "note.text.badge.plus")
        ) { [weak textView] _ in
            guard let textView else { return }
            postSelectionNotification(
                .readerAnnotationRequested, from: textView, range: range, chunkOffset: chunkOffset
            )
        }

        let customMenu = UIMenu(title: "", options: .displayInline, children: [highlightAction, noteAction])
        return UIMenu(children: [customMenu] + suggestedActions)
    }

    /// Posts the content-tapped notification (toolbar toggle).
    static func postContentTappedNotification() {
        NotificationCenter.default.post(name: .readerContentTapped, object: nil)
    }

    /// Shared gesture recognizer delegate answer — always allow simultaneous recognition.
    static func gestureRecognizerShouldRecognizeSimultaneously() -> Bool {
        true
    }
}
