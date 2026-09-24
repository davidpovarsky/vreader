// Purpose: Page-authoritative PDF provider. The facade keeps PDFKit objects on
// the main actor while only strings and structured locator values leave it.

import Foundation

@MainActor
protocol AIPDFDocumentFacading: AnyObject {
    var pageCount: Int { get }
    var currentPageIndex: Int? { get }
    func text(forPage index: Int) async throws -> String
}

@MainActor
final class AIPDFDocumentProvider: AIDocumentProvider {
    let bookFingerprint: DocumentFingerprint
    private let facade: any AIPDFDocumentFacading

    init(
        fingerprint: DocumentFingerprint,
        facade: any AIPDFDocumentFacading
    ) {
        bookFingerprint = fingerprint
        self.facade = facade
    }

    func chunks() async throws -> [AIDocumentChunk] {
        let count = max(0, facade.pageCount)
        var result: [AIDocumentChunk] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            try Task.checkCancellation()
            let text = try await facade.text(forPage: index)
            try Task.checkCancellation()
            result.append(makeChunk(pageIndex: index, text: text))
        }
        return result
    }

    func snapshot() async throws -> AIDocumentSnapshot {
        try Task.checkCancellation()
        let count = max(0, facade.pageCount)
        let pageIndex: Int?
        if count > 0 {
            pageIndex = min(max(facade.currentPageIndex ?? 0, 0), count - 1)
        } else {
            pageIndex = nil
        }

        let currentChunk: AIDocumentChunk?
        if let pageIndex {
            let text = try await facade.text(forPage: pageIndex)
            try Task.checkCancellation()
            currentChunk = makeChunk(pageIndex: pageIndex, text: text)
        } else {
            currentChunk = nil
        }

        let locator = Locator.validated(
            bookFingerprint: bookFingerprint,
            totalProgression: pageIndex.flatMap { index in
                count > 1 ? Double(index) / Double(count - 1) : 0
            },
            page: pageIndex ?? 0
        )!
        let sourceUnitID = currentChunk?.sourceUnitID ?? "pdf:page:0"
        let sectionChunks = currentChunk.map { [$0] } ?? []

        return AIDocumentSnapshot(
            bookFingerprint: bookFingerprint,
            format: .pdf,
            currentLocator: locator,
            currentSourceUnitID: currentChunk?.sourceUnitID,
            currentSectionChunks: sectionChunks,
            visibleChunks: sectionChunks,
            currentChapterLabel: nil,
            currentChapterBounds: nil,
            tocSummary: [],
            readSoFarBoundary: AIReadSoFarBoundary(
                locator: locator,
                sourceUnitID: sourceUnitID,
                sourceUnitIndex: pageIndex,
                localOffsetUTF16: currentChunk?.text.utf16.count
            ),
            exactMappingAvailable: pageIndex != nil
        )
    }

    private func makeChunk(pageIndex: Int, text: String) -> AIDocumentChunk {
        let sourceUnitID = "pdf:page:\(pageIndex)"
        let locator = Locator.validated(
            bookFingerprint: bookFingerprint,
            page: pageIndex
        )!
        return AIDocumentChunk(
            id: AIDocumentChunkFactory.stableID(
                fingerprint: bookFingerprint,
                sourceUnitID: sourceUnitID,
                localStartUTF16: 0
            ),
            bookFingerprintKey: bookFingerprint.canonicalKey,
            sourceUnitID: sourceUnitID,
            sourceUnitIndex: pageIndex,
            text: text,
            locator: locator,
            sourceLabel: "Page \(pageIndex + 1)",
            chapterTitle: nil,
            pageIndex: pageIndex,
            href: nil,
            localStartUTF16: 0,
            localEndUTF16: text.utf16.count,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )
    }
}
