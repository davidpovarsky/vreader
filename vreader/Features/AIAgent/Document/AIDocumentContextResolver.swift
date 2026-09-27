// Purpose: Resolves bounded reader-AI scopes from structured document values.
// Flattened strings are payloads only; source-unit identity remains authoritative.

import Foundation

enum AIDocumentContextScope: Sendable, Equatable {
    case section
    case chapter
    case bookSoFar
}

struct AIDocumentContextCoverage: Sendable, Equatable {
    let includedSourceUnitIDs: [String]
    let droppedSourceUnitIDs: [String]
}

struct AIDocumentResolvedContext: Sendable, Equatable {
    let text: String
    let sourceChunks: [AIDocumentChunk]
    let sourceUnitIDs: [String]
    let currentLocator: Locator
    let exactMappingAvailable: Bool
    let coverage: AIDocumentContextCoverage
}

struct AIDocumentContextResolver: Sendable {
    func resolve(
        snapshot: AIDocumentSnapshot,
        orderedChunks: [AIDocumentChunk],
        scope: AIDocumentContextScope,
        maxUTF16: Int
    ) -> AIDocumentResolvedContext {
        let chunks = orderedChunks.filter {
            $0.bookFingerprintKey == snapshot.bookFingerprint.canonicalKey
                && $0.locator.bookFingerprint == snapshot.bookFingerprint
        }
        let selected: [(AIDocumentChunk, String)]
        switch scope {
        case .section:
            selected = section(snapshot: snapshot, maxUTF16: maxUTF16)
        case .chapter:
            selected = chapter(snapshot: snapshot, chunks: chunks, maxUTF16: maxUTF16)
        case .bookSoFar:
            selected = bookSoFar(snapshot: snapshot, chunks: chunks, maxUTF16: maxUTF16)
        }
        let ids = selected.map { $0.0.sourceUnitID }.uniqued()
        let allIDs = chunks.map(\.sourceUnitID).uniqued()
        return AIDocumentResolvedContext(
            text: selected.map { $0.1 }.filter { !$0.isEmpty }.joined(separator: "\n\n"),
            sourceChunks: selected.map { $0.0 },
            sourceUnitIDs: ids,
            currentLocator: snapshot.currentLocator ?? snapshot.readSoFarBoundary.locator,
            exactMappingAvailable: snapshot.exactMappingAvailable,
            coverage: AIDocumentContextCoverage(
                includedSourceUnitIDs: ids,
                droppedSourceUnitIDs: allIDs.filter { !ids.contains($0) }
            )
        )
    }

    private func section(
        snapshot: AIDocumentSnapshot,
        maxUTF16: Int
    ) -> [(AIDocumentChunk, String)] {
        guard let current = snapshot.currentSectionChunks.first else { return [] }
        let local = snapshot.readSoFarBoundary.localOffsetUTF16
            ?? current.text.utf16.count / 2
        return [(current, clampAround(current.text, offset: local, maxUTF16: maxUTF16))]
    }

    private func chapter(
        snapshot: AIDocumentSnapshot,
        chunks: [AIDocumentChunk],
        maxUTF16: Int
    ) -> [(AIDocumentChunk, String)] {
        guard snapshot.format == .txt || snapshot.format == .md,
              let bounds = snapshot.currentChapterBounds else {
            return section(snapshot: snapshot, maxUTF16: maxUTF16)
        }
        var parts: [(AIDocumentChunk, String)] = []
        for chunk in chunks {
            guard let start = chunk.globalStartUTF16,
                  let end = chunk.globalEndUTF16 else { continue }
            let lower = max(start, bounds.startUTF16)
            let upper = min(end, bounds.endUTF16)
            guard lower < upper else { continue }
            let local = NSRange(location: lower - start, length: upper - lower)
            parts.append((chunk, substring(chunk.text, range: local)))
        }
        return recencyClamp(parts, maxUTF16: maxUTF16)
    }

    private func bookSoFar(
        snapshot: AIDocumentSnapshot,
        chunks: [AIDocumentChunk],
        maxUTF16: Int
    ) -> [(AIDocumentChunk, String)] {
        if snapshot.format == .azw3 || snapshot.format == .mobi {
            return section(snapshot: snapshot, maxUTF16: maxUTF16)
        }
        let boundary = snapshot.readSoFarBoundary
        let policy = AIReadingBoundaryPolicy(mode: .neverReadAhead)
        var parts: [(AIDocumentChunk, String)] = []
        for chunk in chunks {
            guard case .allowed = policy.evaluate(candidate: chunk, boundary: boundary) else {
                continue
            }
            if chunk.sourceUnitID == boundary.sourceUnitID {
                switch snapshot.format {
                case .epub:
                    guard let offset = boundary.localOffsetUTF16 else { continue }
                    parts.append((chunk, prefix(chunk.text, utf16: offset)))
                case .txt, .md:
                    let offset = boundary.localOffsetUTF16
                        ?? boundary.globalOffsetUTF16.map { $0 - (chunk.globalStartUTF16 ?? 0) }
                    guard let offset else { continue }
                    parts.append((chunk, prefix(chunk.text, utf16: offset)))
                default:
                    parts.append((chunk, chunk.text))
                }
            } else {
                parts.append((chunk, chunk.text))
            }
        }
        return recencyClamp(parts, maxUTF16: maxUTF16)
    }

    private func recencyClamp(
        _ parts: [(AIDocumentChunk, String)],
        maxUTF16: Int
    ) -> [(AIDocumentChunk, String)] {
        guard maxUTF16 > 0 else { return [] }
        var remaining = maxUTF16
        var result: [(AIDocumentChunk, String)] = []
        for (chunk, text) in parts.reversed() where remaining > 0 {
            if !result.isEmpty {
                guard remaining > 2 else { break }
                remaining -= 2
            }
            let kept = suffix(text, utf16: remaining)
            guard !kept.isEmpty else { continue }
            result.append((chunk, kept))
            remaining -= kept.utf16.count
        }
        return result.reversed()
    }

    private func clampAround(_ text: String, offset: Int, maxUTF16: Int) -> String {
        let ns = text as NSString
        guard maxUTF16 > 0, ns.length > maxUTF16 else { return maxUTF16 > 0 ? text : "" }
        let center = min(max(offset, 0), ns.length)
        let start = min(max(center - maxUTF16 / 2, 0), ns.length - maxUTF16)
        return safeSubstring(ns, location: start, length: maxUTF16)
    }

    private func prefix(_ text: String, utf16 limit: Int) -> String {
        let ns = text as NSString
        return safeSubstring(ns, location: 0, length: min(max(limit, 0), ns.length))
    }

    private func suffix(_ text: String, utf16 limit: Int) -> String {
        let ns = text as NSString
        let length = min(max(limit, 0), ns.length)
        return safeSubstring(ns, location: ns.length - length, length: length)
    }

    private func substring(_ text: String, range: NSRange) -> String {
        safeSubstring(text as NSString, location: range.location, length: range.length)
    }

    private func safeSubstring(_ text: NSString, location: Int, length: Int) -> String {
        var start = min(max(location, 0), text.length)
        var end = min(max(start + length, start), text.length)
        if start > 0, start < text.length,
           isTrailSurrogate(text.character(at: start)) { start -= 1 }
        if end > start, end < text.length,
           isTrailSurrogate(text.character(at: end)) { end -= 1 }
        return text.substring(with: NSRange(location: start, length: max(0, end - start)))
    }

    private func isTrailSurrogate(_ value: unichar) -> Bool {
        value >= 0xDC00 && value <= 0xDFFF
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
