// Purpose: Exact TXT and rendered-Markdown providers using canonical UTF-16
// display coordinates and the existing txt:/md: segment identity conventions.

import Foundation

@MainActor
final class AITXTDocumentProvider: AIDocumentProvider {
    let bookFingerprint: DocumentFingerprint
    private let text: String
    private var currentLocator: Locator

    init(fingerprint: DocumentFingerprint, text: String, currentLocator: Locator) {
        bookFingerprint = fingerprint
        self.text = text
        self.currentLocator = currentLocator
    }

    func updateCurrentLocator(_ locator: Locator) {
        currentLocator = locator
    }

    func chunks() async throws -> [AIDocumentChunk] {
        try AITextDocumentMapper.chunks(
            fingerprint: bookFingerprint,
            text: text,
            sourcePrefix: "txt"
        )
    }

    func snapshot() async throws -> AIDocumentSnapshot {
        try AITextDocumentMapper.snapshot(
            fingerprint: bookFingerprint,
            text: text,
            sourcePrefix: "txt",
            currentLocator: currentLocator
        )
    }
}

@MainActor
final class AIMarkdownDocumentProvider: AIDocumentProvider {
    let bookFingerprint: DocumentFingerprint
    private let renderedText: String
    private var currentLocator: Locator

    init(fingerprint: DocumentFingerprint, renderedText: String, currentLocator: Locator) {
        bookFingerprint = fingerprint
        self.renderedText = renderedText
        self.currentLocator = currentLocator
    }

    func updateCurrentLocator(_ locator: Locator) {
        currentLocator = locator
    }

    func chunks() async throws -> [AIDocumentChunk] {
        try AITextDocumentMapper.chunks(
            fingerprint: bookFingerprint,
            text: renderedText,
            sourcePrefix: "md"
        )
    }

    func snapshot() async throws -> AIDocumentSnapshot {
        try AITextDocumentMapper.snapshot(
            fingerprint: bookFingerprint,
            text: renderedText,
            sourcePrefix: "md",
            currentLocator: currentLocator
        )
    }
}

private enum AITextDocumentMapper {
    static func chunks(
        fingerprint: DocumentFingerprint,
        text: String,
        sourcePrefix: String
    ) throws -> [AIDocumentChunk] {
        try Task.checkCancellation()
        return try UTF16TextSegmenter.segments(in: text).map { segment in
            try Task.checkCancellation()
            let sourceUnitID = "\(sourcePrefix):segment:\(segment.index)"
            let locator = Locator.validated(
                bookFingerprint: fingerprint,
                charOffsetUTF16: segment.startUTF16,
                charRangeStartUTF16: segment.startUTF16,
                charRangeEndUTF16: segment.endUTF16
            )!
            return AIDocumentChunk(
                id: AIDocumentChunkFactory.stableID(
                    fingerprint: fingerprint,
                    sourceUnitID: sourceUnitID,
                    localStartUTF16: 0
                ),
                bookFingerprintKey: fingerprint.canonicalKey,
                sourceUnitID: sourceUnitID,
                sourceUnitIndex: segment.index,
                text: segment.text,
                locator: locator,
                sourceLabel: nil,
                chapterTitle: nil,
                pageIndex: nil,
                href: nil,
                localStartUTF16: 0,
                localEndUTF16: segment.text.utf16.count,
                globalStartUTF16: segment.startUTF16,
                globalEndUTF16: segment.endUTF16,
                isOCRDerived: false
            )
        }
    }

    static func snapshot(
        fingerprint: DocumentFingerprint,
        text: String,
        sourcePrefix: String,
        currentLocator: Locator
    ) throws -> AIDocumentSnapshot {
        try Task.checkCancellation()
        let allChunks = try chunks(
            fingerprint: fingerprint,
            text: text,
            sourcePrefix: sourcePrefix
        )
        let textLength = text.utf16.count
        let requestedOffset = currentLocator.charOffsetUTF16 ?? 0
        let offset = min(max(requestedOffset, 0), textLength)
        let exactLocator = Locator.validated(
            bookFingerprint: fingerprint,
            charOffsetUTF16: offset,
            textQuote: currentLocator.textQuote,
            textContextBefore: currentLocator.textContextBefore,
            textContextAfter: currentLocator.textContextAfter
        )!
        let current = currentChunk(in: allChunks, offset: offset)
        let sourceUnitID = current?.sourceUnitID ?? "\(sourcePrefix):segment:0"
        let localOffset = current.flatMap { chunk in
            chunk.globalStartUTF16.map { min(max(offset - $0, 0), chunk.text.utf16.count) }
        } ?? 0
        let currentChunks = current.map { [$0] } ?? []

        return AIDocumentSnapshot(
            bookFingerprint: fingerprint,
            format: fingerprint.format,
            currentLocator: exactLocator,
            currentSourceUnitID: current?.sourceUnitID,
            currentSectionChunks: currentChunks,
            visibleChunks: currentChunks,
            currentChapterLabel: nil,
            currentChapterBounds: nil,
            tocSummary: [],
            readSoFarBoundary: AIReadSoFarBoundary(
                locator: exactLocator,
                sourceUnitID: sourceUnitID,
                sourceUnitIndex: current?.sourceUnitIndex,
                localOffsetUTF16: localOffset,
                globalOffsetUTF16: offset
            ),
            exactMappingAvailable: true
        )
    }

    private static func currentChunk(
        in chunks: [AIDocumentChunk],
        offset: Int
    ) -> AIDocumentChunk? {
        if let containing = chunks.first(where: {
            guard let start = $0.globalStartUTF16, let end = $0.globalEndUTF16 else {
                return false
            }
            return start <= offset && offset < end
        }) {
            return containing
        }
        return chunks.last(where: { ($0.globalStartUTF16 ?? .max) <= offset })
            ?? chunks.first
    }
}
