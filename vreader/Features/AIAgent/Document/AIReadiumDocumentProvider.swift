// Purpose: Resource-authoritative Readium EPUB mapping over Sendable value DTOs.
// Href identity chooses the current resource; totalProgression is metadata only.

import Foundation

struct AIReadiumResource: Sendable, Equatable {
    let href: String
    let sourceUnitIndex: Int
    let title: String?
    /// nil means inaccessible; an empty string is an accessible empty resource.
    let text: String?
    let locator: Locator
}

@MainActor
protocol AIReadiumPublicationFacading: AnyObject {
    var currentLocator: Locator? { get }
    func resources() async throws -> [AIReadiumResource]
}

@MainActor
final class AIReadiumDocumentProvider: AIDocumentProvider {
    let bookFingerprint: DocumentFingerprint
    private let facade: any AIReadiumPublicationFacading

    init(
        fingerprint: DocumentFingerprint,
        facade: any AIReadiumPublicationFacading
    ) {
        bookFingerprint = fingerprint
        self.facade = facade
    }

    func chunks() async throws -> [AIDocumentChunk] {
        let resources = try await facade.resources()
        try Task.checkCancellation()
        return try resources.compactMap { resource in
            try Task.checkCancellation()
            guard let text = resource.text else { return nil }
            return makeChunk(resource: resource, text: text)
        }
    }

    func snapshot() async throws -> AIDocumentSnapshot {
        let resources = try await facade.resources()
        try Task.checkCancellation()
        let hrefs = resources.map(\.href)
        let current = normalizedCurrentLocator(against: hrefs)
        let resource = current?.href.flatMap { href in
            resources.first(where: { $0.href == href })
        }
        let currentChunk = resource.flatMap { item in
            item.text.map { makeChunk(resource: item, text: $0) }
        }
        let locator = current
            ?? resource?.locator
            ?? resources.first?.locator
            ?? AIDocumentChunkFactory.emptyLocator(for: bookFingerprint)
        let sourceUnitID = resource.map { "epub:\($0.href)" } ?? "epub:unresolved"
        let sectionChunks = currentChunk.map { [$0] } ?? []

        return AIDocumentSnapshot(
            bookFingerprint: bookFingerprint,
            format: .epub,
            currentLocator: current,
            currentSourceUnitID: resource.map { "epub:\($0.href)" },
            currentSectionChunks: sectionChunks,
            visibleChunks: sectionChunks,
            currentChapterLabel: resource?.title,
            currentChapterBounds: nil,
            tocSummary: resources.compactMap { item in
                item.title.map {
                    AIDocumentTOCSummaryItem(
                        id: "epub:\(item.href)",
                        title: $0,
                        depth: 0,
                        locator: item.locator
                    )
                }
            },
            readSoFarBoundary: AIReadSoFarBoundary(
                locator: locator,
                sourceUnitID: sourceUnitID,
                sourceUnitIndex: resource?.sourceUnitIndex,
                localOffsetUTF16: nil
            ),
            exactMappingAvailable: current != nil && resource?.text != nil
        )
    }

    private func makeChunk(
        resource: AIReadiumResource,
        text: String
    ) -> AIDocumentChunk {
        let sourceUnitID = "epub:\(resource.href)"
        return AIDocumentChunk(
            id: AIDocumentChunkFactory.stableID(
                fingerprint: bookFingerprint,
                sourceUnitID: sourceUnitID,
                localStartUTF16: 0
            ),
            bookFingerprintKey: bookFingerprint.canonicalKey,
            sourceUnitID: sourceUnitID,
            sourceUnitIndex: resource.sourceUnitIndex,
            text: text,
            locator: locator(resource.locator, replacingHref: resource.href),
            sourceLabel: resource.title,
            chapterTitle: resource.title,
            pageIndex: nil,
            href: resource.href,
            localStartUTF16: 0,
            localEndUTF16: text.utf16.count,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )
    }

    private func normalizedCurrentLocator(against hrefs: [String]) -> Locator? {
        guard let current = facade.currentLocator,
              current.bookFingerprint == bookFingerprint,
              let href = current.href,
              let resolved = AIReadiumHrefResolver.resolve(href, against: hrefs)
        else { return nil }
        return locator(current, replacingHref: resolved)
    }

    private func locator(_ source: Locator, replacingHref href: String) -> Locator {
        Locator(
            bookFingerprint: bookFingerprint,
            href: href,
            progression: source.progression,
            totalProgression: source.totalProgression,
            cfi: source.cfi,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: source.textQuote,
            textContextBefore: source.textContextBefore,
            textContextAfter: source.textContextAfter
        ).repairedForCanonicalization()
    }
}

enum AIReadiumHrefResolver {
    /// Mirrors existing Readium navigation: exact, then unique suffix, then
    /// unique basename. Ambiguity returns nil; no progression-based guessing.
    static func resolve(_ stored: String, against hrefs: [String]) -> String? {
        guard !stored.isEmpty, !hrefs.isEmpty else { return nil }
        if hrefs.contains(stored) { return stored }

        let suffixMatches = hrefs.filter { $0.hasSuffix("/" + stored) }
        if suffixMatches.count == 1 { return suffixMatches[0] }
        if suffixMatches.count > 1 { return nil }

        let basename = (stored as NSString).lastPathComponent
        let basenameMatches = hrefs.filter {
            ($0 as NSString).lastPathComponent == basename
        }
        return basenameMatches.count == 1 ? basenameMatches[0] : nil
    }
}
