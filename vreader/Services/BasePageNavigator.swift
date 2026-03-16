// Purpose: Default implementation of PageNavigator with clamping logic.
// Phase B reader VMs will subclass or compose this to get standard
// page navigation behavior (next/prev/jump with clamping + delegate).
//
// Key decisions:
// - currentPage auto-clamps when totalPages is reduced below it.
// - Delegate is only notified when currentPage actually changes.
// - jumpToPage with the same page index is a no-op (no delegate call).
// - progression uses (totalPages - 1) as denominator for correct 0.0..1.0 range.
//
// @coordinates-with PageNavigator.swift

import Foundation

/// Base implementation of PageNavigator with boundary clamping.
@MainActor
class BasePageNavigator: PageNavigator {

    // MARK: - State

    private(set) var currentPage: Int = 0

    var totalPages: Int = 0 {
        didSet {
            // Clamp currentPage when totalPages shrinks
            let maxPage = max(totalPages - 1, 0)
            if currentPage > maxPage {
                currentPage = maxPage
                delegate?.pageNavigator(self, didNavigateToPage: currentPage)
            }
        }
    }

    weak var delegate: (any PageNavigatorDelegate)?

    // MARK: - Computed

    var progression: Double {
        guard totalPages > 1 else { return 0.0 }
        return Double(currentPage) / Double(totalPages - 1)
    }

    // MARK: - Navigation

    func nextPage() {
        let maxPage = max(totalPages - 1, 0)
        let target = currentPage + 1
        guard target <= maxPage, target != currentPage else { return }
        currentPage = target
        delegate?.pageNavigator(self, didNavigateToPage: currentPage)
    }

    func previousPage() {
        let target = currentPage - 1
        guard target >= 0 else { return }
        currentPage = target
        delegate?.pageNavigator(self, didNavigateToPage: currentPage)
    }

    func jumpToPage(_ page: Int) {
        let maxPage = max(totalPages - 1, 0)
        let clamped = max(0, min(page, maxPage))
        guard clamped != currentPage else { return }
        currentPage = clamped
        delegate?.pageNavigator(self, didNavigateToPage: currentPage)
    }
}
