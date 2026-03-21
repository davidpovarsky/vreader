// Purpose: Static JavaScript generators for EPUBWebViewBridge — scroll-to-fraction,
// theme CSS injection/removal, view teardown, and event tracking scripts.
//
// @coordinates-with EPUBWebViewBridge.swift, EPUBWebViewBridgeCoordinator.swift

#if canImport(UIKit)
import WebKit

extension EPUBWebViewBridge {

    // MARK: - Scroll to Fraction

    /// Generates JavaScript that scrolls the page to a vertical fraction (0.0-1.0).
    /// Clamping is applied: negative and NaN values map to 0.0, values > 1.0 map to 1.0.
    static func scrollToFractionJS(_ fraction: Double) -> String {
        let clamped: Double
        if fraction.isNaN || fraction < 0 {
            clamped = 0.0
        } else if fraction > 1.0 {
            clamped = 1.0
        } else {
            clamped = fraction
        }
        return """
        (function() {
            var scrollHeight = Math.max(
                document.documentElement.scrollHeight || 0,
                document.body.scrollHeight || 0
            );
            var clientHeight = document.documentElement.clientHeight || window.innerHeight || 0;
            var maxScroll = scrollHeight - clientHeight;
            if (maxScroll > 0) {
                window.scrollTo(0, maxScroll * \(clamped));
            }
        })();
        """
    }

    /// JavaScript to inject or replace the vreader-theme style element.
    /// `styleTag` is a full `<style id="vreader-theme">…</style>` tag.
    /// We extract the inner CSS and inject via createElement + textContent
    /// to avoid innerHTML-based DOM injection.
    static func injectThemeCSSJS(_ styleTag: String) -> String {
        // Extract CSS content from between <style ...> and </style> tags
        var cssContent = styleTag
        if let startRange = cssContent.range(of: ">", options: .literal),
           let endRange = cssContent.range(of: "</style>", options: .backwards) {
            cssContent = String(cssContent[startRange.upperBound..<endRange.lowerBound])
        }
        let escaped = cssContent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        return """
        (function() {
            var existing = document.getElementById('vreader-theme');
            if (existing) existing.remove();
            var style = document.createElement('style');
            style.id = 'vreader-theme';
            style.textContent = '\(escaped)';
            document.head.appendChild(style);
        })();
        """
    }

    /// JavaScript to remove the vreader-theme style element (when theme is cleared).
    static let removeThemeCSSJS = """
    (function() {
        var existing = document.getElementById('vreader-theme');
        if (existing) existing.remove();
    })();
    """

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "progressHandler"
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "contentTapHandler"
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "selectionChanged"
        )
    }

    // MARK: - JavaScript

    /// Content tap tracking — sends message on non-link clicks for toolbar toggle.
    static let contentTapTrackingJS = """
    (function() {
        document.addEventListener('click', function(e) {
            if (e.target.closest('a')) return;
            window.webkit.messageHandlers.contentTapHandler.postMessage('tap');
        }, false);
    })();
    """

    /// Scroll progress tracking with 100ms throttle to reduce callback churn.
    static let progressTrackingJS = """
    (function() {
        var lastReport = 0;
        function reportProgress() {
            var now = Date.now();
            if (now - lastReport < 100) return;
            lastReport = now;
            var scrollTop = document.documentElement.scrollTop || document.body.scrollTop || 0;
            var scrollHeight = Math.max(
                document.documentElement.scrollHeight || 0,
                document.body.scrollHeight || 0
            );
            var clientHeight = document.documentElement.clientHeight || window.innerHeight || 0;
            var maxScroll = scrollHeight - clientHeight;
            var progress = maxScroll > 0 ? Math.min(Math.max(scrollTop / maxScroll, 0), 1) : 0;
            window.webkit.messageHandlers.progressHandler.postMessage(progress);
        }
        window.addEventListener('scroll', reportProgress, { passive: true });
        // Report initial progress after layout
        setTimeout(reportProgress, 100);
    })();
    """
}
#endif
