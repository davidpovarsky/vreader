// Purpose: UIViewRepresentable wrapping UITextView for TXT/MD document rendering.
// Provides selection range extraction, scroll position -> offset mapping,
// and configurable appearance. Supports both plain text and NSAttributedString.
//
// Key decisions:
// - Uses TextKit 1 (NSLayoutManager) for reliable offset mapping.
// - Non-editable UITextView for reading — selection enabled for highlights.
// - Coordinator handles delegate callbacks (scroll, selection change).
// - All offset conversions delegate to TXTOffsetMapper for testability.
// - Optional `attributedText` parameter: if non-nil, uses it directly (MD reader).
//   If nil, builds plain-text attributed string from `text` + config (TXT reader).
// - Link interaction policy: only http/https URLs are tappable.
//
// @coordinates-with TXTOffsetMapper.swift, TXTChunkedLoader.swift, Locator.swift,
//   MDReaderContainerView.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Configuration for TXT text view appearance.
struct TXTViewConfig: @unchecked Sendable {
    var fontSize: CGFloat = 18
    var fontName: String? = nil // nil = system font
    var lineSpacing: CGFloat = 6
    var textColor: UIColor = UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
    var backgroundColor: UIColor = .white
    var letterSpacing: CGFloat = 0
    var textInset: UIEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

    /// Returns true if rendering-relevant fields match (excludes textInset).
    func renderingEquals(_ other: TXTViewConfig) -> Bool {
        fontSize == other.fontSize
            && fontName == other.fontName
            && lineSpacing == other.lineSpacing
            && textColor == other.textColor
            && backgroundColor == other.backgroundColor
            && letterSpacing == other.letterSpacing
    }
}

/// Callback events from the text view bridge.
@MainActor
protocol TXTTextViewBridgeDelegate: AnyObject {
    /// Called when the user's selection changes. Range is in UTF-16 offsets.
    func selectionDidChange(utf16Range: UTF16Range)
    /// Called when the visible scroll position changes. Offset is in UTF-16 units.
    func scrollPositionDidChange(topCharOffsetUTF16: Int)
}

/// SwiftUI wrapper for a read-only UITextView displaying plain or attributed text.
struct TXTTextViewBridge: UIViewRepresentable {
    let text: String
    /// Optional pre-built attributed string (e.g., from Markdown rendering).
    /// When non-nil, used directly instead of building from `text` + config.
    var attributedText: NSAttributedString?
    let config: TXTViewConfig
    var restoreOffset: Int?
    /// Programmatic scroll target (e.g., from search result navigation).
    /// When this changes in updateUIView, the bridge scrolls to the offset.
    var scrollToOffset: Int?
    /// Temporary highlight range for search result visualization (bug #43).
    /// Applied as a yellow background attribute on the text storage.
    var highlightRange: NSRange?
    /// Whether the current highlight is temporary (search navigation) vs persistent
    /// (user-created). Temporary highlights auto-clear after 3s. (bug #54)
    var highlightIsTemporary: Bool = true
    /// Persisted highlight ranges loaded from DB on file open (bug #55).
    /// Applied as yellow background attributes that survive text rebuilds.
    var persistedHighlights: [NSRange] = []
    weak var delegate: TXTTextViewBridgeDelegate?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.showsVerticalScrollIndicator = true
        textView.alwaysBounceVertical = true
        textView.delegate = context.coordinator
        textView.textContainerInset = config.textInset
        textView.textContainer.lineFragmentPadding = 0

        // Performance: defer off-screen glyph layout for large documents.
        // TextKit 1 will only compute layout for the visible region + buffer.
        textView.layoutManager.allowsNonContiguousLayout = true

        // Tap gesture for toolbar toggle — fires alongside UITextView's own gestures
        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleContentTap)
        )
        tapRecognizer.delegate = context.coordinator
        textView.addGestureRecognizer(tapRecognizer)

        applyText(to: textView)

        // Apply persisted highlights from DB (bug #55).
        // Must happen after applyText sets the attributedText.
        applyPersistedHighlights(to: textView)

        // Restore scroll position if requested (one-shot — never re-applied).
        // Suppress scroll callbacks from the moment text is applied until restore
        // settles, to block TextKit relayout storms (bug #24/#25).
        // Hide the text view until restore completes to prevent the user seeing
        // content at offset 0 before the jump (bug #27).
        if let offset = restoreOffset, offset > 0 {
            context.coordinator.hasRestoredPosition = true
            context.coordinator.suppressScrollCallbacks = true
            textView.alpha = 0
            let coordinator = context.coordinator
            // Phase 1 (t+0.15s): Initial restore after SwiftUI sizes the view.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                // Force TextKit to complete layout before restoring position.
                // This triggers the TextKit 1 relayout synchronously rather than
                // waiting for it to happen asynchronously and destroy our position.
                let textLength = (textView.text as NSString?)?.length ?? 0
                if textLength > 0 {
                    let fullRange = NSRange(location: 0, length: min(textLength, offset + 4096))
                    textView.layoutManager.ensureLayout(forCharacterRange: fullRange)
                }
                coordinator.attemptScrollRestore(in: textView, toCharOffset: offset)
                // Phase 2 (t+0.2s): Brief safety net — re-apply if TextKit
                // relayout happened after ensureLayout. Short delay since
                // ensureLayout already forced layout completion.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    coordinator.attemptScrollRestore(in: textView, toCharOffset: offset)
                    coordinator.suppressScrollCallbacks = false
                    textView.alpha = 1
                }
            }
        } else if let offset = restoreOffset {
            // offset == 0: no need to hide, just mark as restored
            context.coordinator.hasRestoredPosition = true
        }

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Keep delegate reference in sync (SwiftUI may recreate the struct)
        context.coordinator.delegate = delegate

        // Detect if config changed by comparing rendering-relevant fields
        let configChanged = !context.coordinator.lastConfig.renderingEquals(config)

        // Update text or re-apply styling if config changed
        let textChanged = textView.attributedText.string != text
        let attrChanged = attributedText != nil && !textView.attributedText.isEqual(to: attributedText!)
        if textChanged || attrChanged || configChanged {
            applyText(to: textView)
            applyPersistedHighlights(to: textView) // Re-apply after text rebuild (bug #55)
            context.coordinator.lastConfig = config
        }

        // Re-apply inset changes
        if textView.textContainerInset != config.textInset {
            textView.textContainerInset = config.textInset
        }

        // Programmatic scroll from search navigation
        if let target = scrollToOffset,
           target != context.coordinator.lastScrollToTarget {
            context.coordinator.lastScrollToTarget = target
            // Force synchronous layout so charOffsetToScrollOffset returns
            // accurate Y positions (bug #40). Without this, allowsNonContiguousLayout
            // uses estimated line heights for unvisited regions.
            let textLength = (textView.text as NSString?)?.length ?? 0
            if textLength > 0 {
                let rangeEnd = min(textLength, target + 4096)
                textView.layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: rangeEnd))
            }
            context.coordinator.attemptScrollRestore(in: textView, toCharOffset: target)
        }

        // Apply or clear search result highlight (bug #43)
        context.coordinator.applyHighlight(highlightRange, in: textView, isTemporary: highlightIsTemporary)

        // Scroll position restore is one-shot only (handled in makeUIView).
        // Do NOT re-apply restoreOffset here — doing so creates an observation
        // feedback loop: scroll → viewModel.currentOffsetUTF16 changes →
        // SwiftUI re-renders → updateUIView → restoreScrollPosition → scroll (bug #15).
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(delegate: delegate, config: config)
    }

    // MARK: - Private

    /// Applies all persisted highlight ranges as yellow background (bug #55).
    /// Uses layoutManager.addTemporaryAttribute to avoid triggering
    /// UITextViewAccessibility setAttributedText: infinite recursion (bug #47 v5).
    private func applyPersistedHighlights(to textView: UITextView) {
        guard !persistedHighlights.isEmpty else { return }
        let textLength = textView.textStorage.length
        guard textLength > 0 else { return }
        for range in persistedHighlights {
            guard range.location < textLength else { continue }
            let clampedLength = min(range.length, textLength - range.location)
            guard clampedLength > 0 else { continue }
            let safeRange = NSRange(location: range.location, length: clampedLength)
            textView.layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: UIColor.systemYellow.withAlphaComponent(0.4),
                forCharacterRange: safeRange
            )
        }
    }

    private func applyText(to textView: UITextView) {
        if let attributedText {
            // Use pre-built attributed string (from background thread or Markdown rendering)
            textView.attributedText = attributedText
        } else {
            // Fallback: build on main thread (small files or MD reader path)
            textView.attributedText = TXTAttributedStringBuilder.build(text: text, config: config)
        }
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = config.backgroundColor
    }

    // Scroll restore logic is in Coordinator.attemptScrollRestore (supports retry).

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        weak var delegate: TXTTextViewBridgeDelegate?
        var lastConfig: TXTViewConfig
        /// One-shot flag: once true, scroll position restore is never attempted again.
        /// Prevents the observation feedback loop (bug #15, #17) where:
        /// scroll → viewModel update → SwiftUI re-render → restoreScrollPosition → scroll
        var hasRestoredPosition = false
        /// Throttle scroll callbacks to ~10fps to avoid expensive TextKit queries per frame.
        private var lastScrollCallbackTime: CFTimeInterval = 0
        private static let scrollThrottleInterval: CFTimeInterval = 0.1

        /// Retry counter for scroll restore when view has no valid frame yet.
        private var restoreRetryCount = 0
        private static let maxRestoreRetries = 5

        /// Suppresses scroll delegate callbacks during position restore.
        /// TextKit 1 compatibility mode switch causes relayout storms that
        /// reset contentOffset to 0 — these ghost callbacks must be ignored.
        var suppressScrollCallbacks = false
        /// Last programmatic scroll target (search navigation) to avoid re-applying same offset.
        var lastScrollToTarget: Int?
        /// Currently applied highlight range. Used to avoid re-applying the same highlight.
        private var currentHighlightRange: NSRange?
        /// Timer to auto-clear highlight after a delay.
        private var highlightClearTimer: Timer?

        init(delegate: TXTTextViewBridgeDelegate?, config: TXTViewConfig = TXTViewConfig()) {
            self.delegate = delegate
            self.lastConfig = config
        }

        /// Restores scroll position, retrying if the view has no valid frame.
        /// TextKit returns zero-rect line fragments when the text container has
        /// zero width, so charOffsetToScrollOffset returns 0 for all offsets.
        func attemptScrollRestore(in textView: UITextView, toCharOffset offset: Int) {
            guard textView.bounds.width > 0 else {
                guard restoreRetryCount < Self.maxRestoreRetries else { return }
                restoreRetryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.attemptScrollRestore(in: textView, toCharOffset: offset)
                }
                return
            }

            let textLength = (textView.text as NSString?)?.length ?? 0
            let clampedOffset = min(max(offset, 0), textLength)
            let scrollY = TXTOffsetMapper.charOffsetToScrollOffset(
                charOffset: clampedOffset,
                layoutManager: textView.layoutManager,
                textContainer: textView.textContainer
            )
            textView.setContentOffset(CGPoint(x: 0, y: scrollY), animated: false)
        }

        // MARK: - Search Highlight (Bug #43)

        /// Applies or clears a yellow highlight on the text storage.
        /// Temporary highlights (search navigation) auto-clear after 3s.
        /// Persistent highlights (user-created) stay until replaced (bug #54).
        /// Bug #47 v5: Use layoutManager.addTemporaryAttribute instead of
        /// textStorage.addAttribute. Direct textStorage modification triggers
        /// UITextViewAccessibility setAttributedText: → infinite recursion →
        /// EXC_BAD_ACCESS (stack overflow). Temporary attributes are visual-only
        /// and don't modify the document, avoiding the accessibility callback loop.
        func applyHighlight(_ range: NSRange?, in textView: UITextView, isTemporary: Bool = true) {
            // Clear previous highlight
            if let prev = currentHighlightRange {
                let textLength = textView.textStorage.length
                if prev.location + prev.length <= textLength {
                    textView.layoutManager.removeTemporaryAttribute(
                        .backgroundColor,
                        forCharacterRange: prev
                    )
                }
                currentHighlightRange = nil
                highlightClearTimer?.invalidate()
                highlightClearTimer = nil
            }

            guard let range, range.length > 0 else { return }

            let textLength = textView.textStorage.length
            guard range.location < textLength else { return }
            let clampedLength = min(range.length, textLength - range.location)
            guard clampedLength > 0 else { return }
            let safeRange = NSRange(location: range.location, length: clampedLength)

            // Skip if same range already applied
            if currentHighlightRange == safeRange { return }

            textView.layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: UIColor.systemYellow.withAlphaComponent(0.4),
                forCharacterRange: safeRange
            )
            currentHighlightRange = safeRange

            // Only auto-clear temporary highlights (search navigation).
            // User-created highlights persist until replaced or navigated away (bug #54).
            highlightClearTimer?.invalidate()
            highlightClearTimer = nil
            if isTemporary {
                highlightClearTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self, weak textView] _ in
                    DispatchQueue.main.async { [weak self, weak textView] in
                        guard let self, let textView else { return }
                        if let current = self.currentHighlightRange,
                           current.location + current.length <= textView.textStorage.length {
                            textView.layoutManager.removeTemporaryAttribute(
                                .backgroundColor,
                                forCharacterRange: current
                            )
                        }
                        self.currentHighlightRange = nil
                    }
                }
            }
        }

        // MARK: - Content Tap (Toolbar Toggle)

        @objc func handleContentTap(_ gesture: UITapGestureRecognizer) {
            NotificationCenter.default.post(name: .readerContentTapped, object: nil)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: - Link Interaction Policy

        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            // Only allow http and https links
            let scheme = URL.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }

        // MARK: - Edit Menu (Bug #44: Highlight & Note)

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0 else { return UIMenu(children: suggestedActions) }

            let highlightAction = UIAction(
                title: "Highlight",
                image: UIImage(systemName: "highlighter")
            ) { [weak textView] _ in
                guard let textView else { return }
                Self.postSelectionNotification(.readerHighlightRequested, from: textView, range: range)
            }

            let noteAction = UIAction(
                title: "Add Note",
                image: UIImage(systemName: "note.text.badge.plus")
            ) { [weak textView] _ in
                guard let textView else { return }
                Self.postSelectionNotification(.readerAnnotationRequested, from: textView, range: range)
            }

            let customMenu = UIMenu(title: "", options: .displayInline, children: [highlightAction, noteAction])
            return UIMenu(children: [customMenu] + suggestedActions)
        }

        private static func postSelectionNotification(
            _ name: Notification.Name,
            from textView: UITextView,
            range: NSRange
        ) {
            let text = textView.text ?? ""
            let nsText = text as NSString
            guard range.location + range.length <= nsText.length else { return }
            let selectedText = nsText.substring(with: range)
            let info = TextSelectionInfo(
                selectedText: selectedText,
                startUTF16: range.location,
                endUTF16: range.location + range.length
            )
            NotificationCenter.default.post(name: name, object: info)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let nsRange = textView.selectedRange
            if let utf16Range = TXTOffsetMapper.selectionToUTF16Range(
                nsRange: nsRange,
                text: textView.text ?? ""
            ) {
                delegate?.selectionDidChange(utf16Range: utf16Range)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !suppressScrollCallbacks else { return }
            guard let textView = scrollView as? UITextView else { return }

            // Throttle: skip if called within the throttle interval
            let now = CACurrentMediaTime()
            guard now - lastScrollCallbackTime >= Self.scrollThrottleInterval else { return }
            lastScrollCallbackTime = now

            let topOffset = TXTOffsetMapper.scrollOffsetToCharOffset(
                scrollY: scrollView.contentOffset.y,
                layoutManager: textView.layoutManager,
                textContainer: textView.textContainer
            )
            delegate?.scrollPositionDidChange(topCharOffsetUTF16: topOffset)
        }

        /// Flush final scroll position when scrolling ends (deceleration complete).
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            sendScrollPosition(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { sendScrollPosition(scrollView) }
        }

        private func sendScrollPosition(_ scrollView: UIScrollView) {
            guard !suppressScrollCallbacks else { return }
            guard let textView = scrollView as? UITextView else { return }
            lastScrollCallbackTime = CACurrentMediaTime()
            let topOffset = TXTOffsetMapper.scrollOffsetToCharOffset(
                scrollY: scrollView.contentOffset.y,
                layoutManager: textView.layoutManager,
                textContainer: textView.textContainer
            )
            delegate?.scrollPositionDidChange(topCharOffsetUTF16: topOffset)
        }
    }
}
#endif
