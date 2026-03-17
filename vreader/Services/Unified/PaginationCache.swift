// Purpose: In-memory cache for pagination results.
// Keyed by document fingerprint + rendering parameters (font, viewport).
// Invalidates when any parameter changes; supports per-document and bulk clear.
//
// Key decisions:
// - Memory-only — no disk persistence. Pagination is fast enough to recompute.
// - PaginationCacheKey is Hashable, embedding all layout-affecting parameters.
// - PaginationCachePage is a lightweight struct (no text content, just ranges)
//   to keep memory usage low.
// - invalidate(documentFingerprint:) clears all entries for a doc regardless
//   of rendering params — used when document content changes.
//
// @coordinates-with TextKit2Paginator.swift, NativeTextPaginator.swift

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Key identifying a specific pagination result.
/// Any change in these parameters means pages must be recomputed.
struct PaginationCacheKey: Hashable, Sendable {
    let documentFingerprint: String
    let fontSize: CGFloat
    let fontName: String
    let lineSpacing: CGFloat
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat
}

/// Lightweight page descriptor for caching (no text content).
struct PaginationCachePage: Equatable, Sendable {
    let pageIndex: Int
    let charLocation: Int
    let charLength: Int
}

/// In-memory pagination result cache.
final class PaginationCache {

    // MARK: - Storage

    private var store: [PaginationCacheKey: [PaginationCachePage]] = [:]

    // MARK: - Public API

    /// Retrieve cached pages for the given key, or nil if not cached.
    func get(key: PaginationCacheKey) -> [PaginationCachePage]? {
        store[key]
    }

    /// Store pagination results for the given key.
    func set(key: PaginationCacheKey, pages: [PaginationCachePage]) {
        store[key] = pages
    }

    /// Remove all cached entries for a specific document, regardless of
    /// rendering parameters. Use when document content changes.
    func invalidate(documentFingerprint: String) {
        store = store.filter { $0.key.documentFingerprint != documentFingerprint }
    }

    /// Remove all cached entries.
    func invalidateAll() {
        store.removeAll()
    }
}
