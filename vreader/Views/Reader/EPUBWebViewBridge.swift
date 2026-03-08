// Purpose: WKWebView bridge for rendering EPUB XHTML content.
// Loads spine item HTML files with resource access to the extracted EPUB directory.
//
// Key decisions:
// - Uses loadFileURL with allowingReadAccessTo for local CSS/image resources.
// - allowingReadAccessTo uses the extracted root (not opfDir) to cover all resources.
// - Injects JavaScript to report scroll progress back to Swift (throttled at 100ms).
// - Coordinator handles WKScriptMessageHandler for progress callbacks.
// - Navigation delegate reports load errors to the container via onLoadError.
// - Only file:// URLs are allowed for all navigation types.
//
// @coordinates-with: EPUBReaderContainerView.swift, EPUBReaderViewModel.swift

#if canImport(UIKit)
import SwiftUI
import WebKit

/// Weak proxy to break the retain cycle between WKUserContentController and Coordinator.
/// WKUserContentController.add(_:name:) retains the handler strongly; this proxy
/// holds the real handler weakly so the Coordinator can be deallocated.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

/// UIViewRepresentable bridge for EPUB content rendering via WKWebView.
struct EPUBWebViewBridge: UIViewRepresentable {
    /// URL of the XHTML file to load.
    let contentURL: URL
    /// Base directory for resolving relative resources (CSS, images).
    /// Should be the extracted EPUB root directory for widest access.
    let baseDirectory: URL
    /// Optional CSS `<style>` tag to inject for theme overrides.
    var themeCSS: String?
    /// Called when scroll progress changes (0.0...1.0).
    let onProgressChange: @MainActor (Double) -> Void
    /// Called when WKWebView fails to load content.
    let onLoadError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onProgressChange: onProgressChange, onLoadError: onLoadError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        // Add scroll progress tracking script (throttled)
        let script = WKUserScript(
            source: Self.progressTrackingJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(script)
        let weakHandler = WeakScriptMessageHandler(context.coordinator)
        userContentController.add(weakHandler, name: "progressHandler")

        // Add content tap tracking for toolbar toggle
        let tapScript = WKUserScript(
            source: Self.contentTapTrackingJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(tapScript)
        userContentController.add(weakHandler, name: "contentTapHandler")

        config.userContentController = userContentController
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        context.coordinator.themeCSS = themeCSS
        context.coordinator.allowedRoot = baseDirectory
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.accessibilityIdentifier = "epubWebView"

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload if the URL changed
        if context.coordinator.currentURL != contentURL {
            context.coordinator.currentURL = contentURL
            context.coordinator.themeCSS = themeCSS
            webView.loadFileURL(contentURL, allowingReadAccessTo: baseDirectory)
        } else if context.coordinator.themeCSS != themeCSS {
            // Theme changed without URL change — inject or remove CSS live
            context.coordinator.themeCSS = themeCSS
            if let css = themeCSS {
                let js = Self.injectThemeCSSJS(css)
                webView.evaluateJavaScript(js) { _, error in
                    if let error { print("[EPUBWebViewBridge] theme inject error: \(error)") }
                }
            } else {
                // Theme cleared — remove previously injected style element
                webView.evaluateJavaScript(Self.removeThemeCSSJS) { _, error in
                    if let error { print("[EPUBWebViewBridge] theme remove error: \(error)") }
                }
            }
        }
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
    }

    // MARK: - JavaScript

    /// Content tap tracking — sends message on non-link clicks for toolbar toggle.
    private static let contentTapTrackingJS = """
    (function() {
        document.addEventListener('click', function(e) {
            if (e.target.closest('a')) return;
            window.webkit.messageHandlers.contentTapHandler.postMessage('tap');
        }, false);
    })();
    """

    /// Scroll progress tracking with 100ms throttle to reduce callback churn.
    private static let progressTrackingJS = """
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

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var currentURL: URL?
        var themeCSS: String?
        /// Allowed root directory for file:// navigation (scoped to extracted EPUB).
        var allowedRoot: URL?
        private let onProgressChange: @MainActor (Double) -> Void
        private let onLoadError: @MainActor (String) -> Void

        init(
            onProgressChange: @escaping @MainActor (Double) -> Void,
            onLoadError: @escaping @MainActor (String) -> Void
        ) {
            self.onProgressChange = onProgressChange
            self.onLoadError = onLoadError
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "contentTapHandler" {
                NotificationCenter.default.post(name: .readerContentTapped, object: nil)
                return
            }
            guard message.name == "progressHandler",
                  let progress = message.body as? Double else { return }
            Task { @MainActor in
                onProgressChange(progress)
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            // Only allow file:// URLs scoped to the extracted EPUB directory
            guard let url = navigationAction.request.url, url.isFileURL else {
                return .cancel
            }
            // Scope-check: resolved path must be within the allowed root directory
            if let root = allowedRoot {
                let resolvedPath = url.standardizedFileURL.path()
                // Ensure rootPath ends with "/" for strict directory boundary matching
                var rootPath = root.standardizedFileURL.path()
                if !rootPath.hasSuffix("/") { rootPath += "/" }
                guard resolvedPath.hasPrefix(rootPath)
                    || resolvedPath == root.standardizedFileURL.path() else {
                    return .cancel
                }
            }
            return .allow
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            let message = "Failed to load chapter: \(error.localizedDescription)"
            Task { @MainActor in
                onLoadError(message)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            let message = "Chapter loading error: \(error.localizedDescription)"
            Task { @MainActor in
                onLoadError(message)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Inject theme CSS after page finishes loading
            guard let css = themeCSS else { return }
            let js = EPUBWebViewBridge.injectThemeCSSJS(css)
            webView.evaluateJavaScript(js) { _, error in
                if let error { print("[EPUBWebViewBridge] didFinish theme inject error: \(error)") }
            }
        }
    }
}
#endif
