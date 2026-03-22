// Purpose: HighlightRenderer adapter for EPUB format (Phase R4a).
// Translates highlight operations into JavaScript strings for CSS Highlight API
// injection into WKWebView.
//
// Key decisions:
// - Uses onInjectJS callback (set by container) to deliver JS to the bridge.
// - Buffers JS when onInjectJS is nil and flushes when callback is set (bug #77).
// - currentHref must be set before restore() — filters highlights by chapter.
// - Delegates JS generation to EPUBHighlightBridge and EPUBHighlightActions
//   (existing pure-logic modules).
// - No WKWebView dependency — fully testable.
//
// @coordinates-with: HighlightRenderer.swift, EPUBHighlightBridge.swift,
//   EPUBHighlightActions.swift, EPUBReaderContainerView.swift,
//   HighlightCoordinator.swift

#if canImport(UIKit)
import Foundation

/// Highlight renderer for EPUB format.
/// Generates JavaScript for CSS Highlight API operations and delivers
/// via the `onInjectJS` callback. Buffers JS when callback is not yet set.
@MainActor
final class EPUBHighlightRenderer: HighlightRenderer {
    /// Current chapter href for filtering highlights during restore.
    var currentHref: String?

    /// Buffered JS strings awaiting delivery (bug #77: race between .task and highlight creation).
    private var pendingJSBuffer: [String] = []

    /// Callback to inject JS into WKWebView. Set by the container view.
    /// On set, flushes any buffered JS.
    var onInjectJS: ((String) -> Void)? {
        didSet {
            guard let callback = onInjectJS, !pendingJSBuffer.isEmpty else { return }
            let buffered = pendingJSBuffer
            pendingJSBuffer.removeAll()
            for js in buffered {
                callback(js)
            }
        }
    }

    func apply(record: HighlightRecord) {
        guard let js = EPUBHighlightActions.createHighlightJS(for: record) else { return }
        deliverOrBuffer(js)
    }

    func remove(id: UUID) {
        let js = EPUBHighlightBridge.removeHighlightJS(id: id.uuidString)
        deliverOrBuffer(js)
    }

    func restore(records: [HighlightRecord]) {
        guard let href = currentHref, !href.isEmpty else { return }
        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: records, currentHref: href
        )
        if !js.isEmpty {
            deliverOrBuffer(js)
        }
    }

    /// Delivers JS to callback immediately, or buffers if callback is nil.
    private func deliverOrBuffer(_ js: String) {
        if let callback = onInjectJS {
            callback(js)
        } else {
            pendingJSBuffer.append(js)
        }
    }
}
#endif
