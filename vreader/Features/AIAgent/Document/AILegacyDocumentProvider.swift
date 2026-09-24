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
        self.currentSection = currentSection
    }

    func updateCurrentSection(_ section: AILegacyDocumentSection?) {
        currentSection = section
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
}
