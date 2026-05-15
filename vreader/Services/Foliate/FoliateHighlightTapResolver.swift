// Purpose: Resolves a tapped Foliate annotation's CFI back to its persisted
// HighlightRecord's UUID. Feature #53 WI-5.
//
// Foliate-js emits `annotation-show` events with only a CFI when the user
// taps an existing highlight. To post the cross-format
// `.readerHighlightTapped` notification (which carries
// `ReaderHighlightTapEvent { highlightID: UUID, sourceRect: CGRect }`), we
// need to map the tapped CFI back to the highlight's UUID. The resolver is
// a pure function so it can be unit-tested without persistence wiring.
//
// Why this exists separately from `FoliateNavigationHelper.isValidNavigationTarget`:
// that helper validates CFI shape; this one queries a record set. Keeping the
// concerns separate avoids coupling persistence-record knowledge into a
// navigation utility.
//
// @coordinates-with: FoliateReaderContainerView+Highlights.swift,
//   HighlightRecord.swift, AnnotationAnchor.swift, ReaderNotifications.swift

import Foundation

enum FoliateHighlightTapResolver {
    /// Returns the UUID of the highlight whose anchor's CFI matches `cfi`,
    /// or nil if no record matches. Walks the records in order — first match
    /// wins, which is deterministic per the persistence-layer sort order.
    ///
    /// Empty CFI is treated as a no-match (defensive — foliate-host.js
    /// shouldn't post an empty value, but if it does we don't want a
    /// malformed record to accidentally resolve).
    static func resolveHighlightID(
        forCFI cfi: String,
        in records: [HighlightRecord]
    ) -> UUID? {
        guard !cfi.isEmpty else { return nil }
        for record in records {
            // Foliate-rendered formats (AZW3/MOBI/PRC/AZW) reuse the
            // EPUB-flavored anchor since they share the foliate-js render
            // path. The cfi field is what the JS bridge tags the annotation
            // with at render time.
            if case .epub(_, let recordCFI, _) = record.anchor, recordCFI == cfi {
                return record.highlightId
            }
        }
        return nil
    }
}
