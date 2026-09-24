// Purpose: Feature #177 WI-3 live Readium document registration lifecycle.

#if canImport(UIKit)
import ReadiumShared

extension ReadiumEPUBHost {
    var aiDocumentSessionID: AIDocumentSessionID {
        AIDocumentSessionID(
            fingerprintKey: fingerprint.canonicalKey,
            readerToken: readerToken ?? aiDocumentFallbackToken
        )
    }

    func attachAIDocumentFacade(to publication: Publication) {
        detachAIDocumentFacade()
        let facade = AIReadiumPublicationFacade(
            publication: publication,
            fingerprint: fingerprint
        )
        if let lastKnownReadiumLocator {
            facade.updateCurrentLocator(lastKnownReadiumLocator)
        }
        let provider = AIReadiumDocumentProvider(
            fingerprint: fingerprint,
            facade: facade
        )
        aiDocumentFacade = facade
        aiDocumentRegistration = AIDocumentProviderRegistry.shared.attach(
            provider,
            for: aiDocumentSessionID
        )
    }

    func updateAIDocumentLocation(_ locator: ReadiumShared.Locator) {
        aiDocumentFacade?.updateCurrentLocator(locator)
    }

    func detachAIDocumentFacade() {
        if let registration = aiDocumentRegistration {
            AIDocumentProviderRegistry.shared.detach(registration)
        }
        aiDocumentRegistration = nil
        aiDocumentFacade = nil
    }
}
#endif
