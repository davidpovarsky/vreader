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
        let generation = structuredRefreshGeneration
        guard let provider = documentProviderResolver.resolve(session: documentSessionID),
              provider.bookFingerprint.canonicalKey == fingerprintKey else { return nil }
        do {
            // Providers are main-actor facades over live reader objects. Keep
            // access serialized on that actor; parallel `async let` would send
            // the same actor-isolated existential into two child tasks.
            let snapshot = try await provider.snapshot()
            let chunks = try await provider.chunks()
            guard generation == structuredRefreshGeneration,
                  !Task.isCancelled,
                  snapshot.bookFingerprint.canonicalKey == fingerprintKey,
                  let currentProvider = documentProviderResolver.resolve(session: documentSessionID),
                  (currentProvider as AnyObject) === (provider as AnyObject)
            else { return nil }
            let boundedScope: AIDocumentContextScope
            switch scope {
            case .section: boundedScope = .section
            case .chapter: boundedScope = .chapter
            case .bookSoFar, .wholeBook: boundedScope = .bookSoFar
            }
            let maxUTF16: Int
            switch boundedScope {
            case .section:
                maxUTF16 = AIContextBudget.sectionMaxUTF16
            case .chapter, .bookSoFar:
                maxUTF16 = AIContextBudget.defaultMaxUTF16
            }
            return AIDocumentContextResolver().resolve(
                snapshot: snapshot,
                orderedChunks: chunks,
                scope: boundedScope,
                maxUTF16: maxUTF16
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
                self.invalidateWholeBookReadForProviderChange()
                self.invalidateStructuredContext()
                await self.refreshChatContextNow()
            }
        }
    }
}
