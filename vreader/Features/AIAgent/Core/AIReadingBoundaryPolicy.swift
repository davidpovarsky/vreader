// Purpose: One spoiler/read-ahead decision point for all current-book tools.
// Unknown ordering fails closed unless the user explicitly allows whole-book
// access; tools must not reimplement these comparisons independently.

import Foundation

enum AIReadingBoundaryDecision: Equatable, Sendable {
    case allowed(aheadOfReader: Bool?)
    case requiresConfirmation(aheadOfReader: Bool?)
    case denied(aheadOfReader: Bool?)
}

struct AIReadingBoundaryPolicy: Sendable {
    let mode: AIReadAheadMode

    func evaluate(
        candidate: AIDocumentChunk,
        boundary: AIReadSoFarBoundary
    ) -> AIReadingBoundaryDecision {
        let ahead = position(candidate, relativeTo: boundary)
        if ahead == false {
            return .allowed(aheadOfReader: false)
        }

        switch mode {
        case .neverReadAhead:
            return .denied(aheadOfReader: ahead)
        case .askBeforeReadingAhead:
            return .requiresConfirmation(aheadOfReader: ahead)
        case .wholeBookAllowed:
            return .allowed(aheadOfReader: ahead)
        }
    }

    func allowedCandidates(
        from candidates: [AIDocumentChunk],
        boundary: AIReadSoFarBoundary
    ) -> [AIDocumentChunk] {
        candidates.filter {
            if case .allowed = evaluate(candidate: $0, boundary: boundary) {
                return true
            }
            return false
        }
    }

    /// Returns true when ahead, false when at/before, and nil when exact
    /// ordering cannot be established without guessing.
    private func position(
        _ candidate: AIDocumentChunk,
        relativeTo boundary: AIReadSoFarBoundary
    ) -> Bool? {
        let boundaryFingerprint = boundary.locator.bookFingerprint
        guard candidate.bookFingerprintKey == boundaryFingerprint.canonicalKey,
              candidate.locator.bookFingerprint == boundaryFingerprint else {
            return nil
        }

        if let candidateIndex = candidate.sourceUnitIndex,
           let boundaryIndex = boundary.sourceUnitIndex {
            if candidateIndex != boundaryIndex {
                return candidateIndex > boundaryIndex
            }
            return positionWithinSource(candidate, relativeTo: boundary)
        }

        if candidate.sourceUnitID == boundary.sourceUnitID {
            return positionWithinSource(candidate, relativeTo: boundary)
        }

        if let candidateOffset = candidate.globalStartUTF16,
           let boundaryOffset = boundary.globalOffsetUTF16 {
            return candidateOffset > boundaryOffset
        }

        if let candidatePage = candidate.pageIndex ?? candidate.locator.page,
           let boundaryPage = boundary.locator.page {
            return candidatePage > boundaryPage
        }

        if let candidateProgress = candidate.locator.totalProgression,
           let boundaryProgress = boundary.locator.totalProgression {
            return candidateProgress > boundaryProgress
        }

        return nil
    }

    private func positionWithinSource(
        _ candidate: AIDocumentChunk,
        relativeTo boundary: AIReadSoFarBoundary
    ) -> Bool? {
        if let candidateOffset = candidate.localStartUTF16,
           let boundaryOffset = boundary.localOffsetUTF16 {
            return candidateOffset > boundaryOffset
        }

        if let candidateOffset = candidate.globalStartUTF16,
           let boundaryOffset = boundary.globalOffsetUTF16 {
            return candidateOffset > boundaryOffset
        }

        let candidateOffset = candidate.locator.charRangeStartUTF16
            ?? candidate.locator.charOffsetUTF16
        if let candidateOffset,
           let boundaryOffset = boundary.locator.charOffsetUTF16 {
            return candidateOffset > boundaryOffset
        }

        if candidate.locator.href == boundary.locator.href,
           let candidateProgress = candidate.locator.progression,
           let boundaryProgress = boundary.locator.progression {
            return candidateProgress > boundaryProgress
        }

        return nil
    }
}
