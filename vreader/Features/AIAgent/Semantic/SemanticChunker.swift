// Purpose: Deterministic semantic chunker consuming authoritative AIDocumentChunk models.
// Preserves source locators, UTF-16 offsets, and extended grapheme clusters with stable deterministic chunk IDs.

import Foundation
import CryptoKit

struct SemanticChunk: Identifiable, Sendable, Equatable, Codable {
    let id: String
    var chunkID: String { id }
    let bookFingerprintKey: String
    let sourceUnitID: String
    let sourceUnitIndex: Int?
    let text: String
    let locator: Locator
    let sourceLabel: String?
    let chapterTitle: String?
    let pageIndex: Int?
    let href: String?
    let localStartUTF16: Int
    let localEndUTF16: Int
    let isOCRDerived: Bool
}

struct SemanticChunker: Sendable {
    static let chunkerVersion = "v1"

    /// Target character length per chunk (~800-1000 tokens ≈ 3200-4000 UTF-16 code units).
    let targetChunkChars: Int
    /// Character overlap between adjacent chunks (~12%).
    let overlapChars: Int

    init(targetTokens: Int = 800, overlapTokens: Int = 100) {
        self.targetChunkChars = max(500, targetTokens * 4)
        self.overlapChars = max(50, min(overlapTokens * 4, self.targetChunkChars / 2))
    }

    init(targetChunkChars: Int = 3600, overlapChars: Int = 450) {
        self.targetChunkChars = max(500, targetChunkChars)
        self.overlapChars = max(50, min(overlapChars, targetChunkChars / 2))
    }

    /// Chunks a single document chunk.
    func chunk(_ docChunk: AIDocumentChunk, bookFingerprintKey: String) -> [SemanticChunk] {
        chunkSingle(docChunk: docChunk, bookFingerprintKey: bookFingerprintKey)
    }

    /// Splits an array of document chunks into semantic chunks.
    func chunkDocument(chunks: [AIDocumentChunk], bookFingerprintKey: String) -> [SemanticChunk] {
        var result: [SemanticChunk] = []
        for docChunk in chunks {
            result.append(contentsOf: chunkSingle(docChunk: docChunk, bookFingerprintKey: bookFingerprintKey))
        }
        return result
    }

    private func chunkSingle(docChunk: AIDocumentChunk, bookFingerprintKey: String) -> [SemanticChunk] {
        let text = docChunk.text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }

        let baseStart = docChunk.localStartUTF16 ?? 0
        let baseEnd = docChunk.localEndUTF16 ?? text.utf16.count

        // If the chunk is within target budget, return it directly with stable ID
        if text.utf16.count <= targetChunkChars {
            let id = makeChunkID(
                fingerprintKey: bookFingerprintKey,
                sourceUnitID: docChunk.sourceUnitID,
                startUTF16: baseStart,
                endUTF16: baseEnd,
                text: text
            )
            return [SemanticChunk(
                id: id,
                bookFingerprintKey: bookFingerprintKey,
                sourceUnitID: docChunk.sourceUnitID,
                sourceUnitIndex: docChunk.sourceUnitIndex,
                text: text,
                locator: docChunk.locator,
                sourceLabel: docChunk.sourceLabel,
                chapterTitle: docChunk.chapterTitle,
                pageIndex: docChunk.pageIndex,
                href: docChunk.href,
                localStartUTF16: baseStart,
                localEndUTF16: baseEnd,
                isOCRDerived: docChunk.isOCRDerived
            )]
        }

        // Subdivide without splitting extended grapheme clusters
        var semanticChunks: [SemanticChunk] = []
        let characters = Array(text)
        var charStart = 0

        while charStart < characters.count {
            let remaining = characters.count - charStart
            let take = min(remaining, targetChunkChars)
            var charEnd = charStart + take

            // Look for paragraph or sentence break near end if possible
            if charEnd < characters.count {
                var foundBreak = false
                let searchStart = max(charStart + targetChunkChars * 3 / 4, charEnd - 200)
                for i in stride(from: charEnd, through: searchStart, by: -1) {
                    let ch = characters[i]
                    if ch == "\n" || ch == "." || ch == "!" || ch == "?" || ch == "׃" { // including Hebrew Sof Pasuq
                        charEnd = i + 1
                        foundBreak = true
                        break
                    }
                }
                if !foundBreak {
                    charEnd = charStart + take
                }
            }

            let slice = String(characters[charStart..<charEnd])
            let subStartUTF16 = baseStart + String(characters[0..<charStart]).utf16.count
            let subEndUTF16 = subStartUTF16 + slice.utf16.count

            let chunkID = makeChunkID(
                fingerprintKey: bookFingerprintKey,
                sourceUnitID: docChunk.sourceUnitID,
                startUTF16: subStartUTF16,
                endUTF16: subEndUTF16,
                text: slice
            )

            semanticChunks.append(SemanticChunk(
                id: chunkID,
                bookFingerprintKey: bookFingerprintKey,
                sourceUnitID: docChunk.sourceUnitID,
                sourceUnitIndex: docChunk.sourceUnitIndex,
                text: slice,
                locator: docChunk.locator,
                sourceLabel: docChunk.sourceLabel,
                chapterTitle: docChunk.chapterTitle,
                pageIndex: docChunk.pageIndex,
                href: docChunk.href,
                localStartUTF16: subStartUTF16,
                localEndUTF16: subEndUTF16,
                isOCRDerived: docChunk.isOCRDerived
            ))

            if charEnd >= characters.count { break }
            // Advance by (length - overlap)
            let advance = max(1, (charEnd - charStart) - overlapChars)
            charStart += advance
        }

        return semanticChunks
    }

    private func makeChunkID(
        fingerprintKey: String,
        sourceUnitID: String,
        startUTF16: Int,
        endUTF16: Int,
        text: String
    ) -> String {
        let raw = "\(fingerprintKey):\(sourceUnitID):\(startUTF16):\(endUTF16):\(text):\(Self.chunkerVersion)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return "sc_" + hex
    }
}

extension AIDocumentChunk {
    enum Unit {
        case chapter(title: String?)
        case page(number: Int)
        case section(title: String?)
    }

    init(
        unit: Unit,
        locator: Locator,
        text: String,
        isSafeCurrentSection: Bool = true,
        isSafeBookSoFar: Bool = true,
        isAheadOfReader: Bool = false,
        isOCRDerived: Bool = false
    ) {
        let unitID: String
        let unitIndex: Int?
        let title: String?
        let page: Int?
        switch unit {
        case .chapter(let t):
            unitID = "ch:\(t ?? "")"
            unitIndex = nil
            title = t
            page = nil
        case .page(let p):
            unitID = "page:\(p)"
            unitIndex = p
            title = "Page \(p)"
            page = p
        case .section(let s):
            unitID = "sec:\(s ?? "")"
            unitIndex = nil
            title = s
            page = nil
        }

        self.init(
            id: UUID().uuidString,
            bookFingerprintKey: locator.bookFingerprint.canonicalKey,
            sourceUnitID: unitID,
            sourceUnitIndex: unitIndex,
            text: text,
            locator: locator,
            sourceLabel: title,
            chapterTitle: title,
            pageIndex: page,
            href: locator.href,
            localStartUTF16: 0,
            localEndUTF16: text.utf16.count,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: isOCRDerived
        )
    }
}
