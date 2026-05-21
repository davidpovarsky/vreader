// Purpose: Bug #262 / GH #1136 — observes `.foliateTOCAvailable` and feeds
// the converted AZW3/MOBI TOC entries up to `ReaderContainerView`.
//
// Extracted as a dedicated `ViewModifier` because `ReaderContainerView`'s
// `body` is already at SwiftUI's type-inference ceiling; adding the observer
// inline trips "the compiler is unable to type-check this expression in
// reasonable time". This mirrors the `ReaderReTranslateObserver` precedent
// (feature #56 WI-13/14) — heavy observers move out of `body` into a modifier
// so the body expression stays inside the type-checker's budget.
//
// The file-based `ReaderTOCFactory.buildTOC` has no Foliate parser, so it
// returns [] for azw3/mobi; the only TOC source is the live WebView's
// `book-ready` payload, relayed by `FoliateBilingualContainerView` →
// `.foliateTOCAvailable`. Scoped by `fingerprintKey` so a stale post from a
// previous reader cannot overwrite the current book's TOC.
//
// @coordinates-with: ReaderContainerView.swift,
//   FoliateBilingualContainerView.swift, ReaderNotifications.swift,
//   TOCProvider.swift (TOCEntry)

import SwiftUI

/// Relays `.foliateTOCAvailable` entries (scoped by `fingerprintKey`) into a
/// callback the host uses to set `tocEntries` + flip `tocDidLoad`.
struct FoliateTOCAvailableObserver: ViewModifier {
    let bookFingerprintKey: String
    let onEntries: ([TOCEntry]) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .foliateTOCAvailable)
        ) { notification in
            guard let key = notification.userInfo?["fingerprintKey"] as? String,
                  key == bookFingerprintKey,
                  let entries = notification.userInfo?["entries"] as? [TOCEntry],
                  !entries.isEmpty else { return }
            onEntries(entries)
        }
    }
}
