// Purpose: Deterministic semantic chunker consuming authoritative AIDocumentChunk models.
// Preserves source locators, UTF-16 offsets, and extended grapheme clusters with stable deterministic chunk IDs.

import Foundation
import CryptoKit

struct SemanticChunk: Identifiable, Sendable, Equatable, Codable {
    let id: String
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

    init(targetChunkChars: Int = 3600, overlapChars: Int = 450) {
        self.targetChunkChars = max(500, targetChunkChars)
        self.overlapChars = max(50, min(overlapChars, targetChunkChars / 2))
    }

    /// Splits an array of document chunks into semantic chunks.
    func chunkDocument(chunks: [AIDocumentChunk], bookFingerprintKey: String) -> [SemanticChunk] {
        var result: [SemanticChunk] = []
        for docChunk in chunks {
            let subChunks = chunkSingle(docChunk: docChunk, bookFingerprintKey: bookFingerprintKey)
            result.append(contentsOf: subChunks)
        }
        return result
    }

    private func chunkSingle(docChunk: AIDocumentChunk, bookFingerprintKey: String) -> [SemanticChunk] {
        let text = docChunk.text
        if text.isEmpty { return [] }

        // If the chunk is within target budget, return it directly with stable ID
        if text.utf16.count <= targetChunkChars {
            let id = makeChunkID(
                fingerprintKey: bookFingerprintKey,
                sourceUnitID: docChunk.sourceUnitID,
                startUTF16: docChunk.localStartUTF16,
                endUTF16: docChunk.localEndUTF16,
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
                localStartUTF16: docChunk.localStartUTF16,
                localEndUTF16: docChunk.localEndUTF16,
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
            let subStartUTF16 = docChunk.localStartUTF16 + String(characters[0..<charStart]).utf16.count
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
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
