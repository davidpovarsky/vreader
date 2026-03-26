// Purpose: Throwaway spike to validate Foliate-js runs in WKWebView on iOS.
// Tests: ES module loading, book parsing (EPUB + MOBI), relocate events, selection events.
// DELETE THIS FILE after the spike validates the approach.
//
// Approach: Load foliate-reader.html from app bundle via loadFileURL,
// copy book file INTO the bundle directory so it's accessible.
// allowingReadAccessTo: bundleResourceDir gives WKWebView access to all JS files.

import SwiftUI
import WebKit

/// Spike view that opens a book via Foliate-js in WKWebView and logs events.
struct FoliateSpikeView: View {
    let bookURL: URL

    @State private var logs: [String] = []
    @State private var isBookReady = false
    @State private var bookTitle = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(isBookReady ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(isBookReady ? bookTitle : "Loading...")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text("\(logs.count) events")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            FoliateSpikeWebView(
                bookURL: bookURL,
                onLog: { msg in
                    logs.append(msg)
                    if logs.count > 200 { logs.removeFirst() }
                },
                onBookReady: { title in
                    isBookReady = true
                    bookTitle = title
                },
                onError: { msg in
                    errorMessage = msg
                }
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.red)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                        Text(log)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
            }
            .frame(height: 150)
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - WKWebView Wrapper

private struct FoliateSpikeWebView: UIViewRepresentable {
    let bookURL: URL
    let onLog: @MainActor (String) -> Void
    let onBookReady: @MainActor (String) -> Void
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLog: onLog, onBookReady: onBookReady, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        // Register scheme handler for serving JS bundle + book file
        let schemeHandler = FoliateURLSchemeHandler(bookFileURL: bookURL)

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: FoliateURLSchemeHandler.scheme)

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let coordinator = context.coordinator
        for name in [
            "bridge-ready", "book-ready", "relocate", "selection",
            "tap", "annotation-show", "create-overlay", "section-load",
            "external-link", "tts-ssml", "search-result", "search-done",
            "search-progress", "error",
        ] {
            config.userContentController.add(WeakScriptMessageHandler(coordinator), name: name)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true
        webView.navigationDelegate = coordinator
        webView.scrollView.isScrollEnabled = false
        coordinator.webView = webView
        coordinator.bookExt = bookURL.pathExtension.lowercased()

        // Load via scheme handler — the production path
        let readerURL = URL(string: "\(FoliateURLSchemeHandler.scheme)://localhost/index.html")!
        webView.load(URLRequest(url: readerURL))

        Task { @MainActor in
            onLog("[setup] scheme handler, book: \(bookURL.lastPathComponent)")
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var bookExt: String?
        let onLog: @MainActor (String) -> Void
        let onBookReady: @MainActor (String) -> Void
        let onError: @MainActor (String) -> Void

        init(onLog: @escaping @MainActor (String) -> Void,
             onBookReady: @escaping @MainActor (String) -> Void,
             onError: @escaping @MainActor (String) -> Void) {
            self.onLog = onLog
            self.onBookReady = onBookReady
            self.onError = onError
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            let name = message.name
            let body = message.body

            Task { @MainActor in
                switch name {
                case "bridge-ready":
                    onLog("[bridge] JS bridge loaded, opening book...")
                    openBook()

                case "book-ready":
                    if let dict = body as? [String: Any] {
                        let title = dict["title"] as? String ?? "Unknown"
                        let sections = dict["sections"] as? Int ?? 0
                        let layout = dict["layout"] as? String ?? "?"
                        onLog("[book-ready] \"\(title)\" — \(sections) sections, \(layout)")
                        onBookReady(title)
                        _ = try? await webView?.evaluateJavaScript("readerAPI.init({})")
                    }

                case "relocate":
                    if let dict = body as? [String: Any] {
                        let frac = dict["fraction"] as? Double ?? 0
                        let section = dict["sectionIndex"] as? Int ?? 0
                        let total = dict["sectionTotal"] as? Int ?? 0
                        let cfi = dict["cfi"] as? String ?? ""
                        let toc = dict["tocLabel"] as? String ?? ""
                        let pct = String(format: "%.1f%%", frac * 100)
                        onLog("[relocate] \(pct) sec:\(section)/\(total) toc:\(toc) cfi:\(cfi.prefix(40))...")
                    }

                case "selection":
                    if let dict = body as? [String: Any] {
                        let collapsed = dict["collapsed"] as? Bool ?? true
                        if !collapsed {
                            let text = dict["text"] as? String ?? ""
                            let cfi = dict["cfi"] as? String ?? ""
                            onLog("[selection] \"\(text.prefix(50))\" cfi:\(cfi.prefix(40))...")
                        }
                    }

                case "tap":
                    onLog("[tap] content tapped")

                case "create-overlay":
                    if let dict = body as? [String: Any] {
                        onLog("[overlay] section \(dict["index"] as? Int ?? -1)")
                    }

                case "section-load":
                    if let dict = body as? [String: Any] {
                        onLog("[load] section \(dict["index"] as? Int ?? -1)")
                    }

                case "external-link":
                    if let dict = body as? [String: Any] {
                        onLog("[link] \(dict["href"] as? String ?? "")")
                    }

                case "error":
                    if let dict = body as? [String: Any] {
                        let msg = dict["message"] as? String ?? "Unknown"
                        let type = dict["type"] as? String ?? ""
                        onLog("[ERROR] \(type): \(msg)")
                        onError("\(type): \(msg)")
                    }

                default:
                    onLog("[\(name)] \(body)")
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in onLog("[nav-error] \(error.localizedDescription)") }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            Task { @MainActor in
                onLog("[load-error] \(error.localizedDescription)")
                onError(error.localizedDescription)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in onLog("[nav] page loaded") }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if url.scheme == FoliateURLSchemeHandler.scheme || url.scheme == "blob" || url.absoluteString == "about:blank" {
                return .allow
            }
            Task { @MainActor in onLog("[blocked] \(url.absoluteString)") }
            return .cancel
        }

        private func openBook() {
            guard let bookExt else { return }
            // Open book via scheme handler URL — Foliate-js fetches it
            let bookURL = "\(FoliateURLSchemeHandler.scheme)://localhost/book/file"
            let js = """
            (async () => {
                try {
                    const res = await fetch('\(bookURL)');
                    if (!res.ok) throw new Error('fetch failed: ' + res.status);
                    const blob = await res.blob();
                    const file = new File([blob], "book.\(bookExt)");
                    await readerAPI.open(file);
                } catch(e) {
                    window.webkit?.messageHandlers?.error?.postMessage({
                        message: 'openBook: ' + (e.message || e), type: 'open'
                    });
                }
            })()
            """
            webView?.evaluateJavaScript(js) { [weak self] _, error in
                if let error {
                    Task { @MainActor [weak self] in
                        self?.onLog("[eval-error] \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?
    init(_ delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        delegate?.userContentController(c, didReceive: m)
    }
}
