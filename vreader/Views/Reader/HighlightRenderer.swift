// Purpose: Shared protocol for format-specific highlight rendering (Phase R4a).
// Each format (TXT/MD, EPUB, PDF) implements this to apply/remove/restore highlights
// through its native rendering mechanism.
//
// Key decisions:
// - Protocol is @MainActor because all visual operations must happen on the main thread.
// - AnyObject constraint allows reference semantics (renderers hold mutable state).
// - Three operations cover the full highlight lifecycle:
//   apply = newly created, remove = deleted from panel, restore = bulk load on open.
//
// @coordinates-with: TextHighlightRenderer.swift, EPUBHighlightRenderer.swift,
//   PDFHighlightRenderer.swift, HighlightCoordinator.swift

import Foundation

/// Format-agnostic contract for visual highlight operations.
///
/// Each format adapter translates these calls into its native mechanism:
/// - TXT/MD: NSRange mutation on TextReaderUIState
/// - EPUB: CSS Highlight API JS injection
/// - PDF: PDFAnnotation creation/removal
@MainActor
protocol HighlightRenderer: AnyObject {
    /// Visually apply a newly created or persisted highlight.
    func apply(record: HighlightRecord)

    /// Visually remove a highlight by its ID (e.g., deletion from annotations panel).
    func remove(id: UUID)

    /// Restore all saved highlights (e.g., on file/page open).
    func restore(records: [HighlightRecord])
}
