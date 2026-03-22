// Purpose: Protocol defining page-based navigation for all reader formats.
// Phase B surfaces (EPUB, PDF, TXT, MD) will conform to this protocol
// via BasePageNavigator or custom subclasses.
//
// Key decisions:
// - @MainActor isolation — UI-bound, one navigator per reader VM.
// - currentPage is 0-indexed.
// - progression is 0.0..1.0, computed from currentPage / (totalPages - 1).
// - Delegate is weak to avoid retain cycles.
//
// @coordinates-with BasePageNavigator.swift

import Foundation

/// Notified when the current page changes.
@MainActor
protocol PageNavigatorDelegate: AnyObject {
    func pageNavigator(_ navigator: any PageNavigator, didNavigateToPage page: Int)
}

/// Page-based navigation contract for reader view models.
@MainActor
protocol PageNavigator: AnyObject {
    /// The current page index (0-based).
    var currentPage: Int { get }

    /// Total number of pages in the document.
    var totalPages: Int { get set }

    /// Delegate notified on page changes.
    var delegate: (any PageNavigatorDelegate)? { get set }

    /// Advance to the next page. No-op if already at the last page.
    func nextPage()

    /// Go to the previous page. No-op if already at page 0.
    func previousPage()

    /// Jump to a specific page. Values are clamped to valid range.
    func jumpToPage(_ page: Int)

    /// Reading progression as a fraction in 0.0...1.0.
    /// Returns 0.0 when totalPages <= 1.
    var progression: Double { get }
}
