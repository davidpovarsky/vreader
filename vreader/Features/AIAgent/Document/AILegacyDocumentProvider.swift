// Purpose: Intentionally bounded Foliate AZW3/MOBI adapter. It exposes only
// current-section data and never upgrades approximate relocation to exact.

import Foundation

enum AILegacyMappingPrecision: String, Sendable, Equatable {
    case exact
    case approximate
}

struct AILegacyDocumentSection: Sendable, Equatable {
    let sectionIndex: Int
    let href: String?
    let title: String?
    let text: String
    let locator: Locator
    let mappingPrecision: AILegacyMappingPrecision
}

@MainActor
final class AILegacyDocumentProvider: AIDocumentProvider {
    let bookFingerprint: DocumentFingerprint
    private var currentSection: AILegacyDocumentSection?

    init(
        fingerprint: DocumentFingerprint,
        currentSection: AILegacyDocumentSection?
    ) {
        bookFingerprint = fingerprint
        self.currentSection = Self.normalized(currentSection, for: fingerprint)
    }

    func updateCurrentSection(_ section: AILegacyDocumentSection?) {
        currentSection = Self.normalized(section, for: bookFingerprint)
    }

    func chunks() async throws -> [AIDocumentChunk] {
        try Task.checkCancellation()
        return currentSection.map { [makeChunk(from: $0)] } ?? []
    }

    func snapshot() async throws -> AIDocumentSnapshot {
        try Task.checkCancellation()
        let chunk = currentSection.map(makeChunk)
        let sectionChunks = chunk.map { [$0] } ?? []
        let locator = currentSection?.locator
            ?? AIDocumentChunkFactory.emptyLocator(for: bookFingerprint)
        let sourceUnitID = currentSection.map(sourceUnitID) ?? "foliate:unresolved"

        return AIDocumentSnapshot(
            bookFingerprint: bookFingerprint,
            format: bookFingerprint.format,
            currentLocator: currentSection?.locator,
            currentSourceUnitID: chunk?.sourceUnitID,
            currentSectionChunks: sectionChunks,
            visibleChunks: sectionChunks,
            currentChapterLabel: currentSection?.title,
            currentChapterBounds: nil,
            tocSummary: [],
            readSoFarBoundary: AIReadSoFarBoundary(
                locator: locator,
                sourceUnitID: sourceUnitID,
                sourceUnitIndex: currentSection?.sectionIndex,
                localOffsetUTF16: nil
            ),
            exactMappingAvailable: currentSection?.mappingPrecision == .exact
        )
    }

    private func makeChunk(from section: AILegacyDocumentSection) -> AIDocumentChunk {
        let unitID = sourceUnitID(section)
        return AIDocumentChunk(
            id: AIDocumentChunkFactory.stableID(
                fingerprint: bookFingerprint,
                sourceUnitID: unitID,
                localStartUTF16: 0
            ),
            bookFingerprintKey: bookFingerprint.canonicalKey,
            sourceUnitID: unitID,
            sourceUnitIndex: section.sectionIndex,
            text: section.text,
            locator: section.locator,
            sourceLabel: section.title,
            chapterTitle: section.title,
            pageIndex: nil,
            href: section.href,
            localStartUTF16: nil,
            localEndUTF16: nil,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )
    }

    private func sourceUnitID(_ section: AILegacyDocumentSection) -> String {
        "foliate:section:\(section.sectionIndex)"
    }

    /// A legacy section is accepted only when its locator is valid for this
    /// provider. Foreign fingerprints are replaced while every native
    /// relocation field is preserved; malformed locators fail closed.
    fileprivate static func normalized(
        _ section: AILegacyDocumentSection?,
        for fingerprint: DocumentFingerprint
    ) -> AILegacyDocumentSection? {
        guard let section else { return nil }
        let locator = section.locator
        let normalizedLocator: Locator?
        if locator.bookFingerprint == fingerprint {
            normalizedLocator = locator.validate() == nil ? locator : nil
        } else {
            normalizedLocator = Locator.validated(
                bookFingerprint: fingerprint,
                href: locator.href,
                progression: locator.progression,
                totalProgression: locator.totalProgression,
                cfi: locator.cfi,
                page: locator.page,
                charOffsetUTF16: locator.charOffsetUTF16,
                charRangeStartUTF16: locator.charRangeStartUTF16,
                charRangeEndUTF16: locator.charRangeEndUTF16,
                textQuote: locator.textQuote,
                textContextBefore: locator.textContextBefore,
                textContextAfter: locator.textContextAfter
            )
        }
        guard let normalizedLocator else { return nil }
        return AILegacyDocumentSection(
            sectionIndex: section.sectionIndex,
            href: section.href,
            title: section.title,
            text: section.text,
            locator: normalizedLocator,
            mappingPrecision: section.mappingPrecision
        )
    }
}

/// Per-reader lifecycle owner for the bounded live Foliate adapter. The
/// registry's generation-bearing detach token makes an outgoing mount's
/// teardown harmless after a replacement has attached for the same session.
@MainActor
final class AILegacyDocumentRegistration {
    typealias SectionTextLoader = @MainActor @Sendable (Int) async -> String?

    private let fingerprint: DocumentFingerprint
    private let session: AIDocumentSessionID
    private let registry: AIDocumentProviderRegistry
    private var provider: AILegacyDocumentProvider?
    private var registration: AIDocumentRegistration?
    private var updateGeneration: UInt = 0
    private var cachedSectionIndex: Int?
    private var cachedSectionText: String?

    init(
        fingerprint: DocumentFingerprint,
        readerToken: UUID,
        registry: AIDocumentProviderRegistry = .shared
    ) {
        self.fingerprint = fingerprint
        self.session = AIDocumentSessionID(
            fingerprintKey: fingerprint.canonicalKey,
            readerToken: readerToken
        )
        self.registry = registry
    }

    static func matchesSession(
        eventFingerprintKey: String?,
        eventReaderToken: UUID?,
        expectedFingerprintKey: String,
        expectedReaderToken: UUID?
    ) -> Bool {
        guard let eventFingerprintKey,
              let eventReaderToken,
              let expectedReaderToken else { return false }
        return eventFingerprintKey == expectedFingerprintKey
            && eventReaderToken == expectedReaderToken
    }

    /// Updates the current bounded section. Section changes fetch live text;
    /// relocations within the same section reuse its text and refresh only the
    /// locator. Superseded async fetches cannot replace newer relocation data.
    @discardableResult
    func updateCurrentSection(
        sectionIndex: Int,
        href: String?,
        title: String?,
        locator: Locator,
        loadText: @escaping SectionTextLoader
    ) -> Task<Void, Never> {
        updateGeneration &+= 1
        let generation = updateGeneration

        if cachedSectionIndex == sectionIndex, let cachedSectionText {
            install(
                sectionIndex: sectionIndex,
                href: href,
                title: title,
                text: cachedSectionText,
                locator: locator
            )
            return Task {}
        }

        // The reader has already left the installed section. Clear it before
        // awaiting the next live extraction so a slow/failed load cannot expose
        // stale text as the current section.
        provider?.updateCurrentSection(nil)
        cachedSectionIndex = nil
        cachedSectionText = nil

        return Task { @MainActor [weak self] in
            guard let text = await loadText(sectionIndex),
                  !Task.isCancelled,
                  let self,
                  generation == self.updateGeneration else { return }
            self.cachedSectionIndex = sectionIndex
            self.cachedSectionText = text
            self.install(
                sectionIndex: sectionIndex,
                href: href,
                title: title,
                text: text,
                locator: locator
            )
        }
    }

    func teardown() {
        updateGeneration &+= 1
        if let registration {
            registry.detach(registration)
        }
        registration = nil
        provider = nil
        cachedSectionIndex = nil
        cachedSectionText = nil
    }

    private func install(
        sectionIndex: Int,
        href: String?,
        title: String?,
        text: String,
        locator: Locator
    ) {
        let proposed = AILegacyDocumentSection(
            sectionIndex: sectionIndex,
            href: href,
            title: title,
            text: text,
            locator: locator,
            mappingPrecision: .approximate
        )
        guard let section = AILegacyDocumentProvider.normalized(
            proposed, for: fingerprint
        ) else { return }

        if let provider {
            provider.updateCurrentSection(section)
            return
        }
        let provider = AILegacyDocumentProvider(
            fingerprint: fingerprint,
            currentSection: section
        )
        self.provider = provider
        registration = registry.attach(provider, for: session)
    }
}
