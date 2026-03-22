// Purpose: Shared cache for loaded book text content.
// Ensures each book file is parsed only once and shared across coordinators
// (AI, search, TTS, unified reader).
//
// Key decisions:
// - @MainActor for safe access from SwiftUI views.
// - Caches by file URL path to avoid redundant loads.
// - Supports TXT and MD formats via direct file reading.
//   EPUB and PDF are loaded by their respective coordinators.
// - invalidate() clears cache for a specific file URL.
//
// @coordinates-with: ReaderContainerView.swift, ReaderAICoordinator.swift,
//   ReaderUnifiedCoordinator.swift, ReaderSearchCoordinator.swift

import Foundation

/// Shared cache that loads book text content once and serves it to all consumers.
@MainActor
final class BookContentCache {

    /// Cached text content keyed by file URL path.
    private var cache: [String: String] = [:]

    /// Returns cached text content for a book file URL, loading it on first access.
    /// Returns nil if the file cannot be read or is empty.
    func getText(for fileURL: URL, format: String) async -> String? {
        let key = fileURL.path

        if let cached = cache[key] {
            return cached
        }

        let url = fileURL
        let text: String? = await Task.detached {
            switch format.lowercased() {
            case "txt", "md":
                // Use sample-based encoding detection to match TXTService decode path (bug #92)
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                    return nil
                }
                let hintName = TXTService.detectEncodingFromSample(data)
                if let enc = TXTService.encodingFromName(hintName),
                   let decoded = String(data: data, encoding: enc) {
                    return decoded
                }
                return try? String(contentsOf: url, encoding: .utf8)
            default:
                return nil
            }
        }.value

        guard let text, !text.isEmpty else {
            return nil
        }

        cache[key] = text
        return text
    }

    /// Clears cached content for a specific file URL.
    func invalidate(for fileURL: URL) {
        cache.removeValue(forKey: fileURL.path)
    }

    /// Clears all cached content.
    func invalidateAll() {
        cache.removeAll()
    }
}
