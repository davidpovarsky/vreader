// Purpose: WKURLSchemeHandler serving Foliate-js modules and book files to WKWebView.
// Routes vreader-resource:// requests to app bundle (JS) or documents (book file).
//
// Key decisions:
// - Custom scheme avoids loadFileURL's single-directory limitation.
// - JS files served with application/javascript MIME for ES module support.
// - Book files read via memory-mapped Data. TODO: stream for >100MB files.
// - Thread-safe: WKURLSchemeHandler callbacks arrive on arbitrary threads.
//
// URL routing:
//   vreader-resource://reader/index.html → foliate-reader.html from bundle
//   vreader-resource://foliate/view.js   → JS module from bundle
//   vreader-resource://book/file         → book file from sandbox

import Foundation
import WebKit

final class FoliateURLSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {

    static let scheme = "vreader-resource"

    /// Points to the book file in the sandbox. Immutable after init to avoid data races.
    let bookFileURL: URL?

    init(bookFileURL: URL? = nil) {
        self.bookFileURL = bookFileURL
        super.init()
    }

    // Track active tasks for cancellation
    private let lock = NSLock()
    private var activeTasks = Set<ObjectIdentifier>()

    // MARK: - Route Decision (pure, testable)

    /// The routing decision for a given URL path.
    enum RouteKind: Equatable {
        case readerHTML
        case bookFile
        case bundleResource(path: String)
    }

    /// Determines routing from a URL path. Pure function, no side effects.
    static func route(for path: String) -> RouteKind {
        if path == "/index.html" || path == "/" {
            return .readerHTML
        } else if path == "/book/file" {
            return .bookFile
        } else {
            return .bundleResource(path: path)
        }
    }

    /// Splits a URL path into (filename, extension) for bundle resource lookup.
    /// Strips leading "/" and splits on the last ".".
    static func parseBundleResourcePath(_ path: String) -> (filename: String, ext: String)? {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !cleanPath.isEmpty else { return nil }

        if let dotIndex = cleanPath.lastIndex(of: ".") {
            let filename = String(cleanPath[cleanPath.startIndex..<dotIndex])
            let ext = String(cleanPath[cleanPath.index(after: dotIndex)...])
            return (filename, ext)
        } else {
            return (cleanPath, "")
        }
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.lock()
        activeTasks.insert(taskID)
        lock.unlock()

        guard let url = urlSchemeTask.request.url else {
            failTask(urlSchemeTask, taskID: taskID, status: 400, message: "Missing URL")
            return
        }

        let path = url.path

        switch Self.route(for: path) {
        case .readerHTML:
            serveReaderHTML(urlSchemeTask, taskID: taskID)
        case .bookFile:
            serveBookFile(urlSchemeTask, taskID: taskID)
        case .bundleResource(let resourcePath):
            serveBundleResource(urlSchemeTask, taskID: taskID, path: resourcePath)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.lock()
        activeTasks.remove(taskID)
        lock.unlock()
    }

    // MARK: - Routing

    private func serveReaderHTML(_ task: any WKURLSchemeTask, taskID: ObjectIdentifier) {
        guard let url = Bundle.main.url(forResource: "foliate-reader", withExtension: "html",
                                        subdirectory: nil) else {
            // Try looking in Foliate/JS subdirectory
            if let url = findBundleResource(name: "foliate-reader", ext: "html") {
                serveFile(task, taskID: taskID, fileURL: url, mimeType: "text/html")
                return
            }
            failTask(task, taskID: taskID, status: 404, message: "foliate-reader.html not found in bundle")
            return
        }
        serveFile(task, taskID: taskID, fileURL: url, mimeType: "text/html")
    }

    private func serveBundleResource(_ task: any WKURLSchemeTask, taskID: ObjectIdentifier, path: String) {
        guard let parsed = Self.parseBundleResourcePath(path) else {
            failTask(task, taskID: taskID, status: 404, message: "Empty path")
            return
        }

        if let url = findBundleResource(name: parsed.filename, ext: parsed.ext) {
            let mimeType = Self.mimeTypeForExtension(parsed.ext)
            serveFile(task, taskID: taskID, fileURL: url, mimeType: mimeType)
        } else {
            let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
            failTask(task, taskID: taskID, status: 404, message: "Not found: \(cleanPath)")
        }
    }

    private func serveBookFile(_ task: any WKURLSchemeTask, taskID: ObjectIdentifier) {
        guard let bookURL = bookFileURL else {
            failTask(task, taskID: taskID, status: 404, message: "No book file URL set")
            return
        }
        guard FileManager.default.fileExists(atPath: bookURL.path) else {
            failTask(task, taskID: taskID, status: 404, message: "Book file not found")
            return
        }
        let ext = bookURL.pathExtension.lowercased()
        let mimeType = Self.bookMIMEType(ext)
        serveFile(task, taskID: taskID, fileURL: bookURL, mimeType: mimeType)
    }

    // MARK: - File Serving

    private func serveFile(_ task: any WKURLSchemeTask, taskID: ObjectIdentifier,
                           fileURL: URL, mimeType: String) {
        guard isTaskActive(taskID) else { return }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            failTask(task, taskID: taskID, status: 500,
                     message: "Failed to read: \(error.localizedDescription)")
            return
        }

        guard isTaskActive(taskID) else { return }

        let headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache",
        ]

        let response = HTTPURLResponse(
            url: task.request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!

        task.didReceive(response)
        task.didReceive(data)

        guard isTaskActive(taskID) else { return }
        task.didFinish()
        removeTask(taskID)
    }

    // MARK: - Helpers

    private func findBundleResource(name: String, ext: String) -> URL? {
        // Try direct lookup first
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        // Try with path components (e.g., "vendor/zip" → look for "zip.js" in "vendor" subdir)
        let components = name.split(separator: "/")
        if components.count == 2 {
            let subdir = String(components[0])
            let file = String(components[1])
            return Bundle.main.url(forResource: file, withExtension: ext, subdirectory: subdir)
        }
        return nil
    }

    static func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "js", "mjs": return "application/javascript"
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        default: return "application/octet-stream"
        }
    }

    static func bookMIMEType(_ ext: String) -> String {
        switch ext {
        case "epub": return "application/epub+zip"
        case "azw3", "azw", "mobi", "prc": return "application/octet-stream"
        default: return "application/octet-stream"
        }
    }

    private func failTask(_ task: any WKURLSchemeTask, taskID: ObjectIdentifier,
                          status: Int, message: String) {
        guard isTaskActive(taskID) else { return }
        let response = HTTPURLResponse(
            url: task.request.url ?? URL(string: "about:blank")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        )!
        task.didReceive(response)
        task.didReceive(Data(message.utf8))
        task.didFinish()
        removeTask(taskID)
    }

    private func isTaskActive(_ taskID: ObjectIdentifier) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeTasks.contains(taskID)
    }

    private func removeTask(_ taskID: ObjectIdentifier) {
        lock.lock()
        activeTasks.remove(taskID)
        lock.unlock()
    }
}
