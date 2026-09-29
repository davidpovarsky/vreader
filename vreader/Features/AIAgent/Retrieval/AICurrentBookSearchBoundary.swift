// Purpose: Map existing FTS SearchResult locators back to live structured units,
// then release only text authorized by the central retrieval boundary.

import Foundation

struct AIAuthorizedSearchResult: Sendable {
    let result: SearchResult
    let text: String
}

struct AICurrentBookSearchBoundary: Sendable {
    let retrievalBoundary: AICurrentBookRetrievalBoundary

    func authorizedResults(
        _ results: [SearchResult],
        document: AILiveReaderDocument,
        maxResults: Int
    ) async -> [AIAuthorizedSearchResult] {
        var safe: [AIAuthorizedSearchResult] = []
        for result in results.prefix(maxResults) {
            guard !Task.isCancelled else { return [] }
            let candidate = candidate(for: result, chunks: document.chunks)
            guard let released = await retrievalBoundary.authorizedText(
                candidate,
                boundary: document.snapshot.readSoFarBoundary,
                toolName: SearchCurrentBookTool.toolName,
                actionDescription: "Read a current-book search result"
            ), !released.text.isEmpty else { continue }
            safe.append(AIAuthorizedSearchResult(result: result, text: released.text))
        }
        return Task.isCancelled ? [] : safe
    }

    private func candidate(
        for result: SearchResult,
        chunks: [AIDocumentChunk]
    ) -> AIDocumentChunk {
        if let range = exactGlobalRange(result.locator),
           let source = chunks.first(where: {
               guard let start = $0.globalStartUTF16, let end = $0.globalEndUTF16 else {
                   return false
               }
               return start <= range.lowerBound && range.upperBound <= end
           }),
           let sourceStart = source.globalStartUTF16 {
            let local = (range.lowerBound - sourceStart)..<(range.upperBound - sourceStart)
            let text = substring(source.text, range: local)
            return copy(
                source,
                id: result.id,
                text: text,
                locator: result.locator,
                localRange: local,
                globalRange: range
            )
        }

        if let page = result.locator.page,
           let source = chunks.first(where: {
               ($0.pageIndex ?? $0.locator.page) == page
           }) {
            return copy(
                source,
                id: result.id,
                text: ToolResultText.oneLine(result.snippet, maxChars: 400),
                locator: result.locator,
                // PDF search is page-granular. Preserve the page chunk's
                // established range so the exact current page remains inclusive;
                // the snippet itself is still bounded result data, not location
                // truth used to invent a within-page offset.
                localRange: source.localStartUTF16.flatMap { start in
                    source.localEndUTF16.map { start..<$0 }
                },
                globalRange: nil
            )
        }

        if let href = result.locator.href {
            let resolved = AIReadiumHrefResolver.resolve(
                href,
                against: chunks.compactMap { $0.href ?? $0.locator.href }
            )
            if let resolved,
               let source = chunks.first(where: {
                   ($0.href ?? $0.locator.href) == resolved
               }) {
                return copy(
                    source,
                    id: result.id,
                    text: ToolResultText.oneLine(result.snippet, maxChars: 400),
                    locator: result.locator,
                    localRange: nil,
                    globalRange: nil
                )
            }
        }

        return AIDocumentChunk(
            id: result.id,
            bookFingerprintKey: result.locator.bookFingerprint.canonicalKey,
            sourceUnitID: "search:unresolved:\(result.id)",
            sourceUnitIndex: nil,
            text: ToolResultText.oneLine(result.snippet, maxChars: 400),
            locator: result.locator,
            sourceLabel: result.sourceContext,
            chapterTitle: nil,
            pageIndex: result.locator.page,
            href: result.locator.href,
            localStartUTF16: nil,
            localEndUTF16: nil,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )
    }

    private func exactGlobalRange(_ locator: Locator) -> Range<Int>? {
        guard let start = locator.charRangeStartUTF16 ?? locator.charOffsetUTF16,
              let end = locator.charRangeEndUTF16,
              start < end else { return nil }
        return start..<end
    }

    private func copy(
        _ source: AIDocumentChunk,
        id: String,
        text: String,
        locator: Locator,
        localRange: Range<Int>?,
        globalRange: Range<Int>?
    ) -> AIDocumentChunk {
        AIDocumentChunk(
            id: id,
            bookFingerprintKey: source.bookFingerprintKey,
            sourceUnitID: source.sourceUnitID,
            sourceUnitIndex: source.sourceUnitIndex,
            text: text,
            locator: locator,
            sourceLabel: source.sourceLabel,
            chapterTitle: source.chapterTitle,
            pageIndex: source.pageIndex,
            href: source.href,
            localStartUTF16: localRange?.lowerBound,
            localEndUTF16: localRange?.upperBound,
            globalStartUTF16: globalRange?.lowerBound,
            globalEndUTF16: globalRange?.upperBound,
            isOCRDerived: source.isOCRDerived
        )
    }

    private func substring(_ text: String, range: Range<Int>) -> String {
        let ns = text as NSString
        guard range.lowerBound >= 0,
              range.upperBound <= ns.length,
              range.lowerBound < range.upperBound else { return "" }
        return ns.substring(with: NSRange(
            location: range.lowerBound,
            length: range.count
        ))
    }
}
