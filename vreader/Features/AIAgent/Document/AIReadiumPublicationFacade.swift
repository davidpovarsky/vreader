// Purpose: Main-actor facade over the live Readium Publication. It extracts
// per-reading-order value DTOs and never exposes Publication across actors.

#if canImport(ReadiumShared)
import Foundation
@preconcurrency import ReadiumShared

@MainActor
final class AIReadiumPublicationFacade: AIReadiumPublicationFacading {
    private let publication: Publication
    private let fingerprint: DocumentFingerprint
    private var currentReadiumLocator: ReadiumShared.Locator?
    private var cachedResources: [AIReadiumResource]?

    init(publication: Publication, fingerprint: DocumentFingerprint) {
        self.publication = publication
        self.fingerprint = fingerprint
    }

    var currentLocator: Locator? {
        currentReadiumLocator.map(makeVReaderLocator)
    }

    func updateCurrentLocator(_ locator: ReadiumShared.Locator) {
        currentReadiumLocator = locator
    }

    func resources() async throws -> [AIReadiumResource] {
        if let cachedResources { return cachedResources }

        var result: [AIReadiumResource] = []
        result.reserveCapacity(publication.readingOrder.count)
        for (index, link) in publication.readingOrder.enumerated() {
            try Task.checkCancellation()
            let start = await publication.locate(link)
            try Task.checkCancellation()
            let fallback = Locator.validated(
                bookFingerprint: fingerprint,
                href: link.href,
                progression: 0
            )!
            guard let start,
                  let content = publication.content(from: start) else {
                result.append(AIReadiumResource(
                    href: link.href,
                    sourceUnitIndex: index,
                    title: link.title,
                    text: nil,
                    locator: fallback
                ))
                continue
            }

            var pieces: [String] = []
            let iterator = content.iterator()
            var accessible = true
            do {
                while let element = try await iterator.next() {
                    try Task.checkCancellation()
                    guard element.locator.href.string == start.href.string else { break }
                    if let textual = element as? TextualContentElement,
                       let text = textual.text,
                       !text.isEmpty {
                        pieces.append(text)
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                accessible = false
            }

            result.append(AIReadiumResource(
                href: link.href,
                sourceUnitIndex: index,
                title: link.title ?? start.title,
                text: accessible ? pieces.joined(separator: "\n") : nil,
                locator: makeVReaderLocator(start)
            ))
        }
        try Task.checkCancellation()
        cachedResources = result
        return result
    }

    private func makeVReaderLocator(_ readium: ReadiumShared.Locator) -> Locator {
        Locator(
            bookFingerprint: fingerprint,
            href: readium.href.string,
            progression: readium.locations.progression,
            totalProgression: readium.locations.totalProgression,
            cfi: nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: readium.text.highlight,
            textContextBefore: readium.text.before,
            textContextAfter: readium.text.after
        ).repairedForCanonicalization()
    }
}
#endif
