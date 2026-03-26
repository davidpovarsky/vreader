// Purpose: TOC navigation, search result navigation, and position notifications
// for FoliateReaderContainerView.
//
// @coordinates-with: FoliateReaderContainerView.swift, FoliateReaderViewModel.swift

#if canImport(UIKit)
import SwiftUI

extension FoliateReaderContainerView {

    // MARK: - TOC Navigation

    /// Navigate to a TOC entry by its href/CFI.
    /// Posts a notification that the bridge coordinator listens for.
    func navigateToTOCEntry(href: String) {
        guard !href.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let js = FoliateSearchAdapter.goToResultJS(cfi: href)
        NotificationCenter.default.post(
            name: .foliateEvaluateJS,
            object: js
        )
    }

    // MARK: - Search Result Navigation

    /// Navigate to a search result by its CFI.
    func navigateToSearchResult(cfi: String) {
        guard !cfi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let js = FoliateSearchAdapter.goToResultJS(cfi: cfi)
        NotificationCenter.default.post(
            name: .foliateEvaluateJS,
            object: js
        )
    }

    // MARK: - Position Notification

    /// Posts the current reading position for AI panel context.
    func notifyPositionChanged() {
        guard let locator = viewModel.currentLocator() else { return }
        NotificationCenter.default.post(
            name: .readerPositionDidChange,
            object: locator
        )
    }
}

extension Notification.Name {
    /// Posted when a Foliate container needs to evaluate JS in the bridge.
    /// The object is the JS string to evaluate.
    static let foliateEvaluateJS = Notification.Name("foliateEvaluateJS")
}
#endif
