// Purpose: Exact-session structured document resolution and async generation safety.

import Foundation

extension ReaderAICoordinator {
    var compatibilityTextFallback: String {
        switch bookFormat {
        case .txt, .md: return currentTextContent
        default: return fallbackTitle.isEmpty ? "No content available" : fallbackTitle
        }
    }

    func cachedStructuredContext(
        for scope: ChatContextScope
    ) -> AIDocumentResolvedContext? {
        structuredContextCache[scope]
    }

    func invalidateStructuredContext() {
        structuredRefreshGeneration &+= 1
        structuredContextCache.removeAll()
        chatViewModel?.bookContext = nil
        chatViewModel?.pendingCitations = []
    }

    func resolveStructuredContext(
        for scope: ChatContextScope
    ) async -> AIDocumentResolvedContext? {
        guard let provider = documentProviderResolver.resolve(session: documentSessionID),
              provider.bookFingerprint.canonicalKey == fingerprintKey else { return nil }
        do {
            async let snapshotValue = provider.snapshot()
            async let chunksValue = provider.chunks()
            let (snapshot, chunks) = try await (snapshotValue, chunksValue)
            guard snapshot.bookFingerprint.canonicalKey == fingerprintKey else { return nil }
            let boundedScope: AIDocumentContextScope
            switch scope {
            case .section: boundedScope = .section
            case .chapter: boundedScope = .chapter
            case .bookSoFar, .wholeBook: boundedScope = .bookSoFar
            }
            return AIDocumentContextResolver().resolve(
                snapshot: snapshot,
                orderedChunks: chunks,
                scope: boundedScope,
                maxUTF16: AIContextBudget.defaultMaxUTF16
            )
        } catch {
            return nil
        }
    }

    func refreshStructuredContext(for scope: ChatContextScope) async {
        structuredRefreshGeneration &+= 1
        let generation = structuredRefreshGeneration
        let resolved = await resolveStructuredContext(for: scope)
        guard generation == structuredRefreshGeneration else { return }
        if let resolved {
            structuredContextCache[scope] = resolved
            currentLocator = resolved.currentLocator
        } else {
            structuredContextCache.removeValue(forKey: scope)
        }
    }

    func resolveSummaryContext(
        _ scope: SummaryScope
    ) async -> AIDocumentResolvedContext? {
        let chatScope: ChatContextScope
        switch scope {
        case .section: chatScope = .section
        case .chapter: chatScope = .chapter
        case .bookSoFar: chatScope = .bookSoFar
        }
        return await resolveStructuredContext(for: chatScope)
    }

    func startDocumentRegistryObservationIfNeeded() {
        guard documentRegistryObserver == nil else { return }
        documentRegistryObserver = NotificationCenter.default.addObserver(
            forName: .aiDocumentRegistryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let change = notification.object as? AIDocumentRegistryChange else { return }
            Task { @MainActor [weak self] in
                guard let self, change.session == self.documentSessionID else { return }
                self.invalidateStructuredContext()
                await self.refreshChatContextNow()
            }
        }
    }
}
