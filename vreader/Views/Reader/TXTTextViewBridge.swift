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

/// UITextView subclass for highlight-safe text setting (bug #47 v11).
///
/// Problem chain through v5–v10:
/// - textStorage.addAttribute → accessibility recursion → EXC_BAD_ACCESS
/// - Overriding attributedText → Swift 6 @MainActor dispatch queue assert
/// - Reading then writing self.attributedText → os_unfair_lock recursive abort
/// - attributedText setter → UIKit accessibility traversal crash with active selection
///
/// Solution: Build the full attributed string externally, clear selection, then
/// set via textStorage.setAttributedString() which bypasses the attributedText
/// setter's heavy accessibility processing.
final class HighlightableTextView: UITextView {

    /// Guard flag to suppress delegate callbacks during text replacement.
    var isReplacingText = false

    /// Replaces content safely, preserving scroll position (bug #47 v11).
    ///
    /// Key: uses textStorage.setAttributedString() instead of the attributedText
    /// setter, which triggers UIKit accessibility traversal that crashes when
    /// the text view has an active selection (edit menu highlight flow).
    func setHighlightedText(_ attrText: NSAttributedString) {
        isReplacingText = true
        let savedOffset = contentOffset
        // Clear active selection before replacement — UIKit's accessibility
        // system crashes processing stale selection handles/magnifier state
        // during text replacement (bug #47 v11, frame #45 in setter).
        selectedTextRange = nil
        // Use textStorage directly — bypasses the attributedText setter's
        // heavy processing (typing attrs reset, accessibility traversal)
        // that crashes when called during edit menu / selection callbacks.
        textStorage.setAttributedString(attrText)
        contentOffset = savedOffset
        isReplacingText = false
    }
}

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
        let textView = HighlightableTextView()
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

        // Store base text + highlights in coordinator, then build & apply in one shot.
        context.coordinator.baseAttributedText = buildBaseAttributedText()
        context.coordinator.persistedHighlights = persistedHighlights
        context.coordinator.lastAppliedText = text
        context.coordinator.lastAppliedAttrText = attributedText
        applyTextWithHighlights(to: textView, coordinator: context.coordinator)

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

        // Detect changes to source text, config, or highlights
        let configChanged = !context.coordinator.lastConfig.renderingEquals(config)
        let textChanged = text != context.coordinator.lastAppliedText
        let attrChanged = attributedText !== context.coordinator.lastAppliedAttrText
        let persistedChanged = persistedHighlights != context.coordinator.persistedHighlights
        let highlightChanged = highlightRange != context.coordinator.currentHighlightRange

        // Update coordinator state
        let sourceChanged = textChanged || attrChanged || configChanged
        if sourceChanged {
            context.coordinator.baseAttributedText = buildBaseAttributedText()
            context.coordinator.lastConfig = config
            context.coordinator.lastAppliedText = text
            context.coordinator.lastAppliedAttrText = attributedText
        }
        if persistedChanged {
            context.coordinator.persistedHighlights = persistedHighlights
        }
        if highlightChanged {
            context.coordinator.currentHighlightRange = highlightRange
            // Manage auto-clear timer for temporary highlights
            context.coordinator.highlightClearTimer?.invalidate()
            context.coordinator.highlightClearTimer = nil
            if let range = highlightRange, range.length > 0, highlightIsTemporary {
                context.coordinator.highlightClearTimer = Timer.scheduledTimer(
                    withTimeInterval: 3.0, repeats: false
                ) { [weak coordinator = context.coordinator, weak textView] _ in
                    DispatchQueue.main.async {
                        guard let coordinator, let textView else { return }
                        coordinator.currentHighlightRange = nil
                        coordinator.rebuildHighlights(in: textView)
                    }
                }
            }
        }

        // Rebuild text + highlights if anything changed (bug #47 v10)
        if sourceChanged || persistedChanged || highlightChanged {
            applyTextWithHighlights(to: textView, coordinator: context.coordinator)
        }

        // Re-apply inset changes
        if textView.textContainerInset != config.textInset {
            textView.textContainerInset = config.textInset
        }

        // Programmatic scroll from search navigation
        if let target = scrollToOffset,
           target != context.coordinator.lastScrollToTarget {
            context.coordinator.lastScrollToTarget = target
            let textLength = (textView.text as NSString?)?.length ?? 0
            if textLength > 0 {
                let rangeEnd = min(textLength, target + 4096)
                textView.layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: rangeEnd))
            }
            context.coordinator.attemptScrollRestore(in: textView, toCharOffset: target)
        }

        // Scroll position restore is one-shot only (handled in makeUIView).
        // Do NOT re-apply restoreOffset here — doing so creates an observation
        // feedback loop: scroll → viewModel.currentOffsetUTF16 changes →
        // SwiftUI re-renders → updateUIView → restoreScrollPosition → scroll (bug #15).
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(delegate: delegate, config: config)
    }

    // MARK: - Private

    /// Builds the base attributed string from source data (struct properties).
    /// NEVER reads from the textView — always uses struct's text/attributedText/config.
    private func buildBaseAttributedText() -> NSAttributedString {
        if let attributedText {
            return attributedText
        }
        return TXTAttributedStringBuilder.build(text: text, config: config)
    }

    /// Builds the full attributed string with all highlights baked in, then sets it
    /// on the text view. NEVER reads textView.attributedText (bug #47 v10).
    ///
    /// Uses the coordinator's stored highlight state so the timer can also call this.
    private func applyTextWithHighlights(to textView: UITextView, coordinator: Coordinator) {
        let base = coordinator.baseAttributedText ?? buildBaseAttributedText()
        let highlighted = Self.buildHighlightedString(
            base: base,
            persistedHighlights: coordinator.persistedHighlights,
            activeHighlight: coordinator.currentHighlightRange
        )

        // textView is always HighlightableTextView (created in makeUIView).
        // Using textStorage.setAttributedString via setHighlightedText — NEVER
        // the attributedText setter which crashes with active selection (bug #47).
        (textView as! HighlightableTextView).setHighlightedText(highlighted)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = config.backgroundColor
    }

    /// Pure function: builds attributed string with highlight ranges baked in.
    static func buildHighlightedString(
        base: NSAttributedString,
        persistedHighlights: [NSRange],
        activeHighlight: NSRange?
    ) -> NSAttributedString {
        let needsHighlights = !persistedHighlights.isEmpty || activeHighlight != nil
        guard needsHighlights else { return base }

        let mutable = NSMutableAttributedString(attributedString: base)
        let textLength = mutable.length
        let color = UIColor.systemYellow.withAlphaComponent(0.4)

        for range in persistedHighlights {
            guard range.location < textLength else { continue }
            let len = min(range.length, textLength - range.location)
            guard len > 0 else { continue }
            mutable.addAttribute(.backgroundColor, value: color,
                                 range: NSRange(location: range.location, length: len))
        }

        if let range = activeHighlight, range.length > 0, range.location < textLength {
            let len = min(range.length, textLength - range.location)
            if len > 0 {
                mutable.addAttribute(.backgroundColor, value: color,
                                     range: NSRange(location: range.location, length: len))
            }
        }

        return mutable
    }

    // Scroll restore logic is in Coordinator.attemptScrollRestore (supports retry).

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        weak var delegate: TXTTextViewBridgeDelegate?
        var lastConfig: TXTViewConfig
        var lastAppliedAttrText: NSAttributedString?
        var lastAppliedText: String?

        /// Base attributed string (source without highlights). Used by timer to rebuild.
        var baseAttributedText: NSAttributedString?
        /// Persisted highlight ranges from DB (bug #55). Stored for timer rebuild.
        var persistedHighlights: [NSRange] = []
        /// Active search/navigation highlight range (bug #43).
        var currentHighlightRange: NSRange?
        /// Timer to auto-clear temporary highlight after 3s (bug #54).
        var highlightClearTimer: Timer?

        var hasRestoredPosition = false
        private var lastScrollCallbackTime: CFTimeInterval = 0
        private static let scrollThrottleInterval: CFTimeInterval = 0.1
        private var restoreRetryCount = 0
        private static let maxRestoreRetries = 5
        var suppressScrollCallbacks = false
        var lastScrollToTarget: Int?

        init(delegate: TXTTextViewBridgeDelegate?, config: TXTViewConfig = TXTViewConfig()) {
            self.delegate = delegate
            self.lastConfig = config
        }

        /// Rebuilds text + highlights from coordinator state (for timer callback).
        func rebuildHighlights(in textView: UITextView) {
            guard let base = baseAttributedText else { return }
            let highlighted = TXTTextViewBridge.buildHighlightedString(
                base: base,
                persistedHighlights: persistedHighlights,
                activeHighlight: currentHighlightRange
            )
            (textView as! HighlightableTextView).setHighlightedText(highlighted)
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
            // Suppress during text replacement to prevent crash (bug #47 v11)
            if let htv = textView as? HighlightableTextView, htv.isReplacingText { return }
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
            if let htv = scrollView as? HighlightableTextView, htv.isReplacingText { return }
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
            if let htv = scrollView as? HighlightableTextView, htv.isReplacingText { return }
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
