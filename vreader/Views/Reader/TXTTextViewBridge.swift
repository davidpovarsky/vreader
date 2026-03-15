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
//   MDReaderContainerView.swift, HighlightableTextView.swift

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

        // Keep a weak ref for notification-driven highlight clear
        context.coordinator.activeTextView = textView

        // Store base text in coordinator, set source text + highlight ranges separately.
        context.coordinator.baseAttributedText = buildBaseAttributedText()
        context.coordinator.persistedHighlights = persistedHighlights
        context.coordinator.lastAppliedText = text
        context.coordinator.lastAppliedAttrText = attributedText
        // Set highlights first so drawBackground has correct ranges during initial layout.
        Self.applyHighlights(to: textView, coordinator: context.coordinator)
        applySourceText(to: textView, coordinator: context.coordinator)

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

        let htv = textView as! HighlightableTextView

        // Update highlight ranges via layout manager — no text storage mutation (bug #47 v12)
        if persistedChanged || highlightChanged {
            Self.applyHighlights(to: htv, coordinator: context.coordinator)
        }

        // Update source text only when text/config changes (safe — no active selection during config change)
        if sourceChanged {
            applySourceText(to: htv, coordinator: context.coordinator)
        }

        // Re-apply inset changes
        if textView.textContainerInset != config.textInset {
            textView.textContainerInset = config.textInset
        }

        // Programmatic scroll from search navigation
        if let target = scrollToOffset,
           target != context.coordinator.lastScrollToTarget {
            context.coordinator.lastScrollToTarget = target
            // Guard highlight from being cleared by the programmatic scroll (bug #43).
            // Issue 8: Use counter so overlapping scrolls don't clear guard too early.
            context.coordinator.programmaticScrollCount += 1
            let textLength = (textView.text as NSString?)?.length ?? 0
            if textLength > 0 {
                let rangeEnd = min(textLength, target + 4096)
                textView.layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: rangeEnd))
            }
            context.coordinator.attemptScrollRestore(in: textView, toCharOffset: target)
            // Decrement the counter after scroll settles so user scrolls can dismiss normally
            let coordinator = context.coordinator
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                coordinator.programmaticScrollCount = max(0, coordinator.programmaticScrollCount - 1)
            }
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

    /// Sets source text on the text view (no highlights — those are in the layout manager).
    private func applySourceText(to textView: HighlightableTextView, coordinator: Coordinator) {
        let base = coordinator.baseAttributedText ?? buildBaseAttributedText()
        textView.setSourceText(base)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = config.backgroundColor
    }

    /// Updates highlight visualization via the layout manager (bug #47 v12).
    /// NEVER modifies text storage — completely safe during active selection.
    private static func applyHighlights(to textView: HighlightableTextView, coordinator: Coordinator) {
        textView.setHighlightRanges(
            persisted: coordinator.persistedHighlights,
            active: coordinator.currentHighlightRange
        )
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
        /// Weak reference to the text view, used by notification-based highlight clear.
        weak var activeTextView: UITextView?
        /// Observation token for searchHighlightClear notification.
        nonisolated(unsafe) var highlightClearObserver: NSObjectProtocol?

        var hasRestoredPosition = false
        private var lastScrollCallbackTime: CFTimeInterval = 0
        private static let scrollThrottleInterval: CFTimeInterval = 0.1
        private var restoreRetryCount = 0
        private static let maxRestoreRetries = 5
        var suppressScrollCallbacks = false
        var lastScrollToTarget: Int?
        /// Guards search highlight from being cleared by programmatic scroll (bug #43 regression).
        /// Uses a counter instead of a boolean (Issue 8) so overlapping programmatic scrolls
        /// don't clear the guard prematurely — each scroll increments the counter, and
        /// the guard is only lowered when all scrolls have settled (counter reaches 0).
        var programmaticScrollCount = 0

        init(delegate: TXTTextViewBridgeDelegate?, config: TXTViewConfig = TXTViewConfig()) {
            self.delegate = delegate
            self.lastConfig = config
            super.init()

            // Observe searchHighlightClear to dismiss temporary highlights on new search
            highlightClearObserver = NotificationCenter.default.addObserver(
                forName: .searchHighlightClear, object: nil, queue: .main
            ) { [weak self] _ in
                self?.clearSearchHighlightIfTemporary()
                if let tv = self?.activeTextView {
                    self?.rebuildHighlights(in: tv)
                }
            }
        }

        deinit {
            // Coordinator is @MainActor-isolated via UITextViewDelegate; deinit is nonisolated.
            // Use assumeIsolated to satisfy strict concurrency for non-Sendable property access.
            MainActor.assumeIsolated {
                if let observer = highlightClearObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                highlightClearTimer?.invalidate()
                highlightClearTimer = nil
            }
        }

        /// Clears the current temporary search highlight and cancels any auto-clear timer.
        /// Skips clearing when `programmaticScrollCount > 0` (bug #43 regression fix,
        /// Issue 8: counter-based guard) so that search navigation scroll doesn't
        /// immediately dismiss the highlight.
        func clearSearchHighlightIfTemporary() {
            guard programmaticScrollCount <= 0 else { return }
            highlightClearTimer?.invalidate()
            highlightClearTimer = nil
            currentHighlightRange = nil
        }

        /// Rebuilds highlight visualization from coordinator state (for timer callback).
        /// Uses layout manager drawing — NEVER modifies text storage (bug #47 v12).
        func rebuildHighlights(in textView: UITextView) {
            guard let htv = textView as? HighlightableTextView else { return }
            htv.setHighlightRanges(persisted: persistedHighlights, active: currentHighlightRange)
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
            clearSearchHighlightIfTemporary()
            if let tv = gesture.view as? UITextView {
                rebuildHighlights(in: tv)
            }
            TXTBridgeShared.postContentTappedNotification()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            TXTBridgeShared.gestureRecognizerShouldRecognizeSimultaneously()
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
            TXTBridgeShared.buildReaderEditMenu(
                range: range, textView: textView, suggestedActions: suggestedActions
            )
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

            // Clear temporary search highlight on user scroll
            if currentHighlightRange != nil {
                clearSearchHighlightIfTemporary()
                rebuildHighlights(in: textView)
            }

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
