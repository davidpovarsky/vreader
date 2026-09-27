// Purpose: Exact-session lifecycle owner for live TXT and rendered-Markdown AI providers.

import Foundation

@MainActor
final class AITextDocumentRegistration {
    private let fingerprint: DocumentFingerprint
    private let session: AIDocumentSessionID
    private let registry: AIDocumentProviderRegistry
    private var provider: (any AIDocumentProvider)?
    private var registration: AIDocumentRegistration?
    private var generation: UInt = 0

    init(
        fingerprint: DocumentFingerprint,
        readerToken: UUID,
        registry: AIDocumentProviderRegistry = .shared
    ) {
        self.fingerprint = fingerprint
        session = AIDocumentSessionID(
            fingerprintKey: fingerprint.canonicalKey,
            readerToken: readerToken
        )
        self.registry = registry
    }

    func beginTXTAttach(
        loadText: @escaping @Sendable () async throws -> String,
        locator: Locator,
        chapterBounds: ChapterBounds?
    ) -> Task<Void, Never> {
        generation &+= 1
        let expected = generation
        return Task { @MainActor [weak self] in
            guard let text = try? await loadText(),
                  !Task.isCancelled,
                  let self,
                  expected == self.generation else { return }
            self.install(AITXTDocumentProvider(
                fingerprint: self.fingerprint,
                text: text,
                currentLocator: locator,
                currentChapterBounds: chapterBounds
            ))
        }
    }

    func attachMarkdown(
        renderedText: String,
        locator: Locator,
        chapterBounds: ChapterBounds?
    ) {
        generation &+= 1
        install(AIMarkdownDocumentProvider(
            fingerprint: fingerprint,
            renderedText: renderedText,
            currentLocator: locator,
            currentChapterBounds: chapterBounds
        ))
    }

    func update(locator: Locator, chapterBounds: ChapterBounds?) {
        if let provider = provider as? AITXTDocumentProvider {
            provider.updateCurrentLocator(locator, chapterBounds: chapterBounds)
        } else if let provider = provider as? AIMarkdownDocumentProvider {
            provider.updateCurrentLocator(locator, chapterBounds: chapterBounds)
        }
    }

    func teardown() {
        generation &+= 1
        if let registration { registry.detach(registration) }
        registration = nil
        provider = nil
    }

    private func install(_ newProvider: any AIDocumentProvider) {
        if let registration { registry.detach(registration) }
        provider = newProvider
        registration = registry.attach(newProvider, for: session)
    }
}
