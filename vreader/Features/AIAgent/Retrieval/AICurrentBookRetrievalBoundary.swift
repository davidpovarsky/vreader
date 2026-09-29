// Purpose: Central spoiler boundary enforcement for all current-book tools.
// AIReadingBoundaryPolicy remains the ordering authority; this type adds exact
// partial-overlap clipping and the shared WI-5 confirmation release path.

import Foundation

enum AIRetrievalOverlapPolicy: Equatable, Sendable {
    case clipExactText
    case atomic
}

struct AICurrentBookRetrievalBoundary: Sendable {
    let authorizationGate: AIAgentToolExecutionGate

    func authorizedText(
        _ candidate: AIDocumentChunk,
        boundary: AIReadSoFarBoundary,
        toolName: String,
        actionDescription: String,
        overlapPolicy: AIRetrievalOverlapPolicy = .clipExactText
    ) async -> AIDocumentChunk? {
        guard !Task.isCancelled else { return nil }

        if let overlap = exactOverlap(candidate, boundary: boundary) {
            let outcome = await authorizeUnreadPortion(
                candidate,
                boundary: boundary,
                toolName: toolName,
                actionDescription: actionDescription,
                probe: overlap.aheadProbe
            )
            if outcome == .allowed { return Task.isCancelled ? nil : candidate }
            guard overlapPolicy == .clipExactText, !Task.isCancelled else {
                return nil
            }
            return clippedPrefix(candidate, safeUTF16: overlap.safeTextUTF16)
        }

        let outcome = await authorizationGate.authorizeReadAhead(
            candidate: candidate,
            boundary: boundary,
            context: readAheadContext(
                candidate,
                toolName: toolName,
                actionDescription: actionDescription
            )
        )
        return outcome == .allowed && !Task.isCancelled ? candidate : nil
    }

    func authorizedTexts(
        _ candidates: [AIDocumentChunk],
        boundary: AIReadSoFarBoundary,
        toolName: String,
        actionDescription: String,
        overlapPolicy: AIRetrievalOverlapPolicy = .clipExactText
    ) async -> [AIDocumentChunk] {
        var safe: [AIDocumentChunk] = []
        for candidate in candidates {
            guard !Task.isCancelled else { return [] }
            if let released = await authorizedText(
                candidate,
                boundary: boundary,
                toolName: toolName,
                actionDescription: actionDescription,
                overlapPolicy: overlapPolicy
            ) {
                safe.append(released)
            }
        }
        return Task.isCancelled ? [] : safe
    }

    private struct ExactOverlap {
        let safeTextUTF16: Int
        let aheadProbe: AIDocumentChunk
    }

    private func exactOverlap(
        _ candidate: AIDocumentChunk,
        boundary: AIReadSoFarBoundary
    ) -> ExactOverlap? {
        guard candidate.bookFingerprintKey == boundary.locator.bookFingerprint.canonicalKey,
              candidate.locator.bookFingerprint == boundary.locator.bookFingerprint,
              candidate.sourceUnitID == boundary.sourceUnitID else { return nil }

        if let start = candidate.globalStartUTF16,
           let end = candidate.globalEndUTF16,
           let offset = boundary.globalOffsetUTF16,
           start < offset, offset < end {
            return ExactOverlap(
                safeTextUTF16: offset - start,
                aheadProbe: replacingRangeStart(
                    candidate,
                    globalStart: offset + 1,
                    localStart: boundary.localOffsetUTF16.map { $0 + 1 }
                )
            )
        }
        if let start = candidate.localStartUTF16,
           let end = candidate.localEndUTF16,
           let offset = boundary.localOffsetUTF16,
           start < offset, offset < end {
            return ExactOverlap(
                safeTextUTF16: offset - start,
                aheadProbe: replacingRangeStart(
                    candidate,
                    globalStart: boundary.globalOffsetUTF16.map { $0 + 1 },
                    localStart: offset + 1
                )
            )
        }
        return nil
    }

    private func authorizeUnreadPortion(
        _ candidate: AIDocumentChunk,
        boundary: AIReadSoFarBoundary,
        toolName: String,
        actionDescription: String,
        probe: AIDocumentChunk
    ) async -> AIAgentToolAuthorizationOutcome {
        await authorizationGate.authorizeReadAhead(
            candidate: probe,
            boundary: boundary,
            context: readAheadContext(
                candidate,
                toolName: toolName,
                actionDescription: actionDescription
            )
        )
    }

    private func readAheadContext(
        _ candidate: AIDocumentChunk,
        toolName: String,
        actionDescription: String
    ) -> AIToolAuthorizationContext {
        AIAgentToolAuthorization.context(
            toolName: toolName,
            actionDescription: actionDescription,
            category: .readAhead,
            bookFingerprintKey: candidate.bookFingerprintKey,
            sourceLocator: candidate.locator
        )
    }

    private func clippedPrefix(
        _ candidate: AIDocumentChunk,
        safeUTF16: Int
    ) -> AIDocumentChunk? {
        guard safeUTF16 > 0 else { return nil }
        let text = utf16Prefix(candidate.text, limit: safeUTF16)
        guard !text.isEmpty else { return nil }
        let kept = text.utf16.count
        let localEnd = candidate.localStartUTF16.map { $0 + kept }
        let globalEnd = candidate.globalStartUTF16.map { $0 + kept }
        let locator = Locator.validated(
            bookFingerprint: candidate.locator.bookFingerprint,
            href: candidate.locator.href,
            progression: candidate.locator.progression,
            totalProgression: candidate.locator.totalProgression,
            cfi: candidate.locator.cfi,
            page: candidate.locator.page,
            charOffsetUTF16: candidate.locator.charOffsetUTF16,
            charRangeStartUTF16: candidate.locator.charRangeStartUTF16,
            charRangeEndUTF16: globalEnd ?? candidate.locator.charRangeEndUTF16,
            textQuote: candidate.locator.textQuote,
            textContextBefore: candidate.locator.textContextBefore,
            textContextAfter: candidate.locator.textContextAfter
        ) ?? candidate.locator
        return AIDocumentChunk(
            id: candidate.id,
            bookFingerprintKey: candidate.bookFingerprintKey,
            sourceUnitID: candidate.sourceUnitID,
            sourceUnitIndex: candidate.sourceUnitIndex,
            text: text,
            locator: locator,
            sourceLabel: candidate.sourceLabel,
            chapterTitle: candidate.chapterTitle,
            pageIndex: candidate.pageIndex,
            href: candidate.href,
            localStartUTF16: candidate.localStartUTF16,
            localEndUTF16: localEnd,
            globalStartUTF16: candidate.globalStartUTF16,
            globalEndUTF16: globalEnd,
            isOCRDerived: candidate.isOCRDerived
        )
    }

    private func replacingRangeStart(
        _ candidate: AIDocumentChunk,
        globalStart: Int?,
        localStart: Int?
    ) -> AIDocumentChunk {
        AIDocumentChunk(
            id: candidate.id,
            bookFingerprintKey: candidate.bookFingerprintKey,
            sourceUnitID: candidate.sourceUnitID,
            sourceUnitIndex: candidate.sourceUnitIndex,
            text: candidate.text,
            locator: candidate.locator,
            sourceLabel: candidate.sourceLabel,
            chapterTitle: candidate.chapterTitle,
            pageIndex: candidate.pageIndex,
            href: candidate.href,
            localStartUTF16: localStart ?? candidate.localStartUTF16,
            localEndUTF16: candidate.localEndUTF16,
            globalStartUTF16: globalStart ?? candidate.globalStartUTF16,
            globalEndUTF16: candidate.globalEndUTF16,
            isOCRDerived: candidate.isOCRDerived
        )
    }

    private func utf16Prefix(_ text: String, limit: Int) -> String {
        let ns = text as NSString
        var end = min(max(limit, 0), ns.length)
        if end > 0, end < ns.length,
           (0xDC00...0xDFFF).contains(ns.character(at: end)) {
            end -= 1
        }
        return ns.substring(with: NSRange(location: 0, length: end))
    }
}
