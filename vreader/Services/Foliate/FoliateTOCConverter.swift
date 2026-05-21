// Purpose: Converts Foliate-js hierarchical TOC tree to flat [TOCEntry] list.
// Foliate-js provides TOC as nested FoliateTOCItem; VReader uses flat TOCEntry with levels.
//
// Key decisions:
// - Depth-first traversal preserves reading order (parent before children).
// - Labels are trimmed; whitespace-only entries are skipped.
// - sequenceIndex is globally sequential for unique IDs.
// - Uses LocatorFactory.epub() for locators (Foliate-js uses EPUB-style hrefs for all formats).
//
// @coordinates-with: FoliateTypes.swift, TOCProvider.swift, LocatorFactory.swift

import Foundation

/// Converts Foliate-js TOC tree to flat VReader TOCEntry list.
enum FoliateTOCConverter {

    /// Convert Foliate-js TOC tree to flat [TOCEntry] list with levels.
    ///
    /// - Parameters:
    ///   - items: Root-level TOC items from Foliate-js (may contain nested subitems).
    ///   - fingerprint: Document fingerprint for locator construction.
    /// - Returns: Flat array of TOCEntry in depth-first order with level tracking.
    static func convert(
        _ items: [FoliateTOCItem],
        fingerprint: DocumentFingerprint
    ) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        var sequenceIndex = 0
        flatten(items, level: 0, fingerprint: fingerprint, entries: &entries, sequenceIndex: &sequenceIndex)
        return entries
    }

    // MARK: - Private

    /// Recursively flattens TOC items depth-first.
    private static func flatten(
        _ items: [FoliateTOCItem],
        level: Int,
        fingerprint: DocumentFingerprint,
        entries: inout [TOCEntry],
        sequenceIndex: inout Int
    ) {
        for item in items {
            let trimmedLabel = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
            // Bug #262 Codex round-1 fix: foliate-host.js serializes a missing
            // href as '' (serializeTOC: `href: item.href ?? ''`). An empty
            // href produces a tappable TOC row whose navigation no-ops
            // (`FoliateNavSeek.navigationTarget` rejects empty/whitespace
            // hrefs). Skip emitting an entry for an empty-href node, but STILL
            // recurse into its subitems so clickable children of a
            // non-navigable parent (a common TOC shape) remain visible.
            let trimmedHref = item.href.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLabel.isEmpty, !trimmedHref.isEmpty {
                if let locator = LocatorFactory.epub(
                    fingerprint: fingerprint,
                    href: trimmedHref,
                    progression: 0.0
                ) {
                    entries.append(TOCEntry(
                        title: trimmedLabel,
                        level: level,
                        locator: locator,
                        sequenceIndex: sequenceIndex
                    ))
                    sequenceIndex += 1
                }
            }
            if !item.subitems.isEmpty {
                flatten(item.subitems, level: level + 1, fingerprint: fingerprint, entries: &entries, sequenceIndex: &sequenceIndex)
            }
        }
    }
}
