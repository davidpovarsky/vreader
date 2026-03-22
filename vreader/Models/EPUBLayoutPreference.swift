// Purpose: User-facing layout preference for EPUB rendering — scroll or paged.
// Distinct from EPUBLayout (which describes the publication's intrinsic layout type).
//
// Key decisions:
// - String-backed RawRepresentable for UserDefaults persistence.
// - Default is .scroll (preserves existing behavior).
// - .paged enables CSS multi-column pagination in WKWebView.
//
// @coordinates-with: ReaderSettingsStore.swift, EPUBWebViewBridge.swift,
//   EPUBPaginationHelper.swift

import Foundation

/// User preference for EPUB reading layout mode.
enum EPUBLayoutPreference: String, Codable, Sendable, Hashable, CaseIterable {
    /// Traditional vertical scrolling (default).
    case scroll
    /// Horizontal paged layout using CSS multi-column.
    case paged
}
