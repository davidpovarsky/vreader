// Purpose: WKWebView bridge for rendering EPUB XHTML content.
// Loads spine item HTML files with resource access to the extracted EPUB directory.
//
// Key decisions:
// - Uses loadFileURL with allowingReadAccessTo for local CSS/image resources.
// - allowingReadAccessTo uses the extracted root (not opfDir) to cover all resources.
// - Injects JavaScript to report scroll progress back to Swift (throttled at 100ms).
// - Supports scroll-to-fraction via JS injection for intra-chapter seeking.
// - Injects selection tracking and highlight API JS for text highlighting (WI-007).
// - Supports paged layout via CSS multi-column pagination (WI-B06).
//   In paged mode, pagination CSS is injected and navigation uses scrollLeft.
// - Coordinator handles WKScriptMessageHandler for progress, tap, and selection callbacks.
// - Navigation delegate reports load errors to the container via onLoadError.
// - Only file:// URLs are allowed for all navigation types.
//
// @coordinates-with: EPUBReaderContainerView.swift, EPUBReaderViewModel.swift,
//   EPUBHighlightBridge.swift, EPUBPaginationHelper.swift

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
    /// Scroll fraction (0.0-1.0) to scroll to after the chapter loads.
    /// Set by the container view when seeking within a chapter.
    var scrollFraction: Double?
    /// Current chapter href for anchor construction in selection events.
    var currentHref: String?
    /// Called when scroll progress changes (0.0...1.0).
    let onProgressChange: @MainActor (Double) -> Void
    /// Called when WKWebView fails to load content.
    let onLoadError: @MainActor (String) -> Void
    /// Called when the user selects text in the EPUB content.
    var onSelectionEvent: (@MainActor (ReaderSelectionEvent) -> Void)?
    /// Called after a page finishes loading (for highlight restoration).
    /// The closure receives a JS evaluator that runs JavaScript on the WKWebView.
    var onPageDidFinishLoad: (@MainActor (@escaping (String) -> Void) -> Void)?
    /// JavaScript to evaluate on next updateUIView cycle.
    /// Container sets this to inject highlight JS after persist.
    /// Bridge evaluates it and the container should clear via onPendingJSCompleted.
    var pendingJS: String?
    /// Called after pendingJS has been evaluated so the container can clear state.
    var onPendingJSCompleted: (@MainActor () -> Void)?
    /// Whether paged layout is enabled (CSS multi-column pagination).
    var isPaged: Bool = false
    /// Page index to navigate to in paged mode (0-based).
    var paginationPage: Int?
    /// Called when pagination is set up with total page count (paged mode only).
    var onPaginationReady: (@MainActor (Int) -> Void)?

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

        // Add selection tracking and highlight API JS (WI-007)
        let selectionScript = WKUserScript(
            source: EPUBHighlightBridge.selectionTrackingJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(selectionScript)
        userContentController.add(weakHandler, name: "selectionChanged")

        let highlightScript = WKUserScript(
            source: EPUBHighlightBridge.highlightAPIJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(highlightScript)

        config.userContentController = userContentController
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        context.coordinator.themeCSS = themeCSS
        context.coordinator.allowedRoot = baseDirectory
        context.coordinator.currentHref = currentHref
        context.coordinator.onSelectionEvent = onSelectionEvent
        context.coordinator.onPageDidFinishLoad = onPageDidFinishLoad
        context.coordinator.isPaged = isPaged
        context.coordinator.onPaginationReady = onPaginationReady
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.accessibilityIdentifier = "epubWebView"

        // Disable vertical scrolling in paged mode
        if isPaged {
            webView.scrollView.isScrollEnabled = false
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Keep coordinator in sync with current props
        context.coordinator.currentHref = currentHref
        context.coordinator.onSelectionEvent = onSelectionEvent
        context.coordinator.onPageDidFinishLoad = onPageDidFinishLoad
        context.coordinator.isPaged = isPaged
        context.coordinator.onPaginationReady = onPaginationReady

        // Update scroll enabled state when layout mode changes
        webView.scrollView.isScrollEnabled = !isPaged

        // Only reload if the URL changed
        if context.coordinator.currentURL != contentURL {
            context.coordinator.currentURL = contentURL
            context.coordinator.themeCSS = themeCSS
            // Store scroll fraction to apply after the page finishes loading
            context.coordinator.pendingScrollFraction = scrollFraction
            context.coordinator.pendingPaginationPage = paginationPage
            webView.loadFileURL(contentURL, allowingReadAccessTo: baseDirectory)
        } else if isPaged, let page = paginationPage,
                  page != context.coordinator.pendingPaginationPage {
            // Paged mode: navigate to specific page
            context.coordinator.pendingPaginationPage = page
            let viewportWidth = webView.bounds.width
            let js = EPUBPaginationHelper.navigateToPageJS(
                page: page, viewportWidth: viewportWidth
            )
            webView.evaluateJavaScript(js) { _, error in
                if let error { print("[EPUBWebViewBridge] page nav error: \(error)") }
            }
        } else if let fraction = scrollFraction,
                  fraction != context.coordinator.pendingScrollFraction {
            // Same URL but scroll fraction changed — scroll immediately via JS
            context.coordinator.pendingScrollFraction = fraction
            let js = Self.scrollToFractionJS(fraction)
            webView.evaluateJavaScript(js) { _, error in
                if let error { print("[EPUBWebViewBridge] scroll error: \(error)") }
            }
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

        // Evaluate pending JS from container (e.g., highlight injection after persist)
        if let js = pendingJS {
            webView.evaluateJavaScript(js) { _, error in
                if let error { print("[EPUBWebViewBridge] pendingJS error: \(error)") }
            }
            Task { @MainActor in
                onPendingJSCompleted?()
            }
        }
    }

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
        /// Scroll fraction to apply after the next page load completes.
        var pendingScrollFraction: Double?
        /// Page index to navigate to after pagination setup (paged mode).
        var pendingPaginationPage: Int?
        /// Allowed root directory for file:// navigation (scoped to extracted EPUB).
        var allowedRoot: URL?
        /// Current chapter href for anchor construction.
        var currentHref: String?
        /// Callback for text selection events.
        var onSelectionEvent: (@MainActor (ReaderSelectionEvent) -> Void)?
        /// Callback to restore highlights after page loads.
        /// Provides a JS evaluator so the container can inject restore scripts.
        var onPageDidFinishLoad: (@MainActor (@escaping (String) -> Void) -> Void)?
        /// Whether paged layout mode is active.
        var isPaged = false
        /// Called when pagination is ready with total page count.
        var onPaginationReady: (@MainActor (Int) -> Void)?
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
            if message.name == "selectionChanged" {
                handleSelectionMessage(message.body)
                return
            }
            guard message.name == "progressHandler",
                  let progress = message.body as? Double else { return }
            Task { @MainActor in
                onProgressChange(progress)
            }
        }

        private func handleSelectionMessage(_ body: Any) {
            guard let parsed = EPUBHighlightBridge.parseSelectionMessage(body) else { return }
            let href = currentHref ?? ""
            let event = EPUBHighlightBridge.makeSelectionEvent(
                selectedText: parsed.selectedText,
                href: href,
                cfi: "",
                range: parsed.range,
                sourceRect: parsed.sourceRect
            )
            Task { @MainActor in
                onSelectionEvent?(event)
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
            if let css = themeCSS {
                let js = EPUBWebViewBridge.injectThemeCSSJS(css)
                webView.evaluateJavaScript(js) { _, error in
                    if let error { print("[EPUBWebViewBridge] didFinish theme inject error: \(error)") }
                }
            }

            if isPaged {
                // Paged mode: inject pagination CSS, then query total pages
                setupPagination(webView: webView)
            } else {
                // Scroll mode: scroll to pending fraction after page layout
                if let fraction = pendingScrollFraction, fraction > 0 {
                    pendingScrollFraction = nil
                    let scrollJS = EPUBWebViewBridge.scrollToFractionJS(fraction)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        webView.evaluateJavaScript(scrollJS) { _, error in
                            if let error { print("[EPUBWebViewBridge] scroll error: \(error)") }
                        }
                    }
                }
            }

            // Notify container that the page finished loading (for highlight restoration).
            // Provide a JS evaluator so the container can inject restore scripts.
            Task { @MainActor in
                onPageDidFinishLoad?({ js in
                    webView.evaluateJavaScript(js) { _, error in
                        if let error { print("[EPUBWebViewBridge] restore error: \(error)") }
                    }
                })
            }
        }

        /// Injects pagination CSS and queries total page count after layout settles.
        private func setupPagination(webView: WKWebView) {
            let viewportWidth = webView.bounds.width
            let viewportHeight = webView.bounds.height
            guard viewportWidth > 0, viewportHeight > 0 else { return }

            let injectJS = EPUBPaginationHelper.injectPaginationCSSJS(
                viewportWidth: viewportWidth, viewportHeight: viewportHeight
            )
            webView.evaluateJavaScript(injectJS) { [weak self] _, error in
                if let error {
                    print("[EPUBWebViewBridge] pagination CSS error: \(error)")
                    return
                }
                // Delay to allow column layout to settle before querying page count
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    guard let self else { return }
                    let totalPagesJS = EPUBPaginationHelper.totalPagesJS(
                        viewportWidth: viewportWidth
                    )
                    webView.evaluateJavaScript(totalPagesJS) { [weak self] result, error in
                        guard let self else { return }
                        if let error {
                            print("[EPUBWebViewBridge] totalPages query error: \(error)")
                            return
                        }
                        let totalPages = (result as? Int) ?? 1
                        Task { @MainActor in
                            self.onPaginationReady?(totalPages)
                        }
                        // Navigate to pending page if set
                        if let page = self.pendingPaginationPage, page > 0 {
                            self.pendingPaginationPage = nil
                            let navJS = EPUBPaginationHelper.navigateToPageJS(
                                page: page, viewportWidth: viewportWidth
                            )
                            webView.evaluateJavaScript(navJS) { _, error in
                                if let error {
                                    print("[EPUBWebViewBridge] page nav error: \(error)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
