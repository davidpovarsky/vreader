// Purpose: HighlightRenderer adapter for EPUB format (Phase R4a).
// Translates highlight operations into JavaScript strings for CSS Highlight API
// injection into WKWebView.
//
// Key decisions:
// - Uses onInjectJS callback (set by container) to deliver JS to the bridge.
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
/// via the `onInjectJS` callback.
@MainActor
final class EPUBHighlightRenderer: HighlightRenderer {
    /// Current chapter href for filtering highlights during restore.
    var currentHref: String?

    /// Callback to inject JS into WKWebView. Set by the container view.
    var onInjectJS: ((String) -> Void)?

    func apply(record: HighlightRecord) {
        guard let js = EPUBHighlightActions.createHighlightJS(for: record) else { return }
        onInjectJS?(js)
    }

    func remove(id: UUID) {
        let js = EPUBHighlightBridge.removeHighlightJS(id: id.uuidString)
        onInjectJS?(js)
    }

    func restore(records: [HighlightRecord]) {
        guard let href = currentHref, !href.isEmpty else { return }
        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: records, currentHref: href
        )
        if !js.isEmpty {
            onInjectJS?(js)
        }
    }
}
#endif
