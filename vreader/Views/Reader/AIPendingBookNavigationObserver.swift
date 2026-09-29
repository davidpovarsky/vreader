// Purpose: Deliver an AI open_book target only after the new reader reports its
// exact document provider attaches, then re-enter the established locator seam.

import SwiftUI

struct AIPendingBookNavigationObserver: ViewModifier {
    let fingerprintKey: String
    let readerToken: UUID

    func body(content: Content) -> some View {
        content
            .task {
                await deliverIfReady()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .aiDocumentRegistryDidChange)
            ) { notification in
                guard let change = notification.object as? AIDocumentRegistryChange,
                      change.kind == .attached,
                      change.session == sessionID else { return }
                Task { @MainActor in
                    await deliverIfReady()
                }
            }
    }

    @MainActor
    private var sessionID: AIDocumentSessionID {
        AIDocumentSessionID(
            fingerprintKey: fingerprintKey,
            readerToken: readerToken
        )
    }

    @MainActor
    private func deliverIfReady() async {
        await AIPendingBookNavigationStore.shared.claim(
            fingerprintKey: fingerprintKey,
            readerToken: readerToken
        )
        guard !Task.isCancelled,
              AIDocumentProviderRegistry.shared.resolve(session: sessionID) != nil,
              let target = await AIPendingBookNavigationStore.shared.take(
                  for: fingerprintKey,
                  readerToken: readerToken
              ) else { return }
        NotificationCenter.default.post(
            name: .readerNavigateToLocator,
            object: target,
            userInfo: ["readerToken": readerToken]
        )
    }
}
