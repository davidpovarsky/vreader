// Purpose: Streaming chapter index builder for TXT files.
// Ports Legado's 512KB block scanning pattern to Swift.
//
// Key decisions:
// - Memory-mapped Data input (no full-file String allocation).
// - 512KB block size matching Legado's bufferSize = 512_000.
// - Block boundary handling: walk back to last 0x0A to avoid splitting multi-byte chars.
// - Regex applied per-block with .anchorsMatchLines for ^ and $ matching.
// - Synthetic fallback: 50KB chapters at paragraph breaks when no rule matches.
// - BOM detection: skip 3-byte UTF-8 BOM or 2-byte UTF-16 BOM.
//
// @coordinates-with: TXTChapterIndex.swift, TXTTocRuleEngine.swift, TXTTocRule.swift

import Foundation

/// Builds a TXTChapterIndex by streaming through file data in blocks.
enum TXTChapterIndexBuilder {

    /// Block size for streaming (512KB, matching Legado).
    static let bufferSize = 512_000

    /// Target size for synthetic chapters when no TOC rule matches.
    static let syntheticChapterSize = 50_000

    // MARK: - Public API

    /// Builds a chapter index from raw file data. Uses regex rule if provided and >= 2 matches;
    /// otherwise falls back to synthetic ~50KB chapters at paragraph breaks.
    static func build(
        data: Data,
        encoding: String.Encoding,
        encodingName: String,
        rule: TXTTocRule?
    ) -> TXTChapterIndex {
        let totalBytes = Int64(data.count)

        guard !data.isEmpty else {
            return TXTChapterIndex(
                chapters: [],
                totalBytes: 0,
                detectedEncoding: encodingName
            )
        }

        let bomLength = detectBOMLength(data: data)

        // Try regex-based chapter detection
        if let rule = rule,
           let regex = try? NSRegularExpression(
               pattern: rule.rule,
               options: [.anchorsMatchLines]
           ) {
            let chapters = buildWithRegex(
                data: data,
                encoding: encoding,
                regex: regex,
                bomLength: bomLength,
                totalBytes: totalBytes
            )
            if chapters.count >= 2 {
                return TXTChapterIndex(
                    chapters: chapters,
                    totalBytes: totalBytes,
                    detectedEncoding: encodingName
                )
            }
        }

        // Fallback: synthetic chapters
        let chapters = buildSynthetic(
            data: data,
            bomLength: bomLength,
            totalBytes: totalBytes
        )
        return TXTChapterIndex(
            chapters: chapters,
            totalBytes: totalBytes,
            detectedEncoding: encodingName
        )
    }
}

// MARK: - Regex-Based Chapter Detection

private extension TXTChapterIndexBuilder {

    /// Streams data in blocks, applies regex, records chapter boundaries as byte offsets.
    /// Ported from Legado's TextFile.analyze(pattern:).
    static func buildWithRegex(
        data: Data,
        encoding: String.Encoding,
        regex: NSRegularExpression,
        bomLength: Int,
        totalBytes: Int64
    ) -> [TXTChapter] {
        var chapters: [TXTChapter] = []
        var curByteOffset = Int64(bomLength)

        while curByteOffset < totalBytes {
            let readStart = Int(curByteOffset)
            var readEnd = min(readStart + bufferSize, Int(totalBytes))

            if readEnd < Int(totalBytes) {
                readEnd = walkBackToNewline(data: data, from: readEnd, floor: readStart)
            }

            let blockData = data[readStart..<readEnd]
            guard let blockText = String(data: blockData, encoding: encoding) else {
                curByteOffset = Int64(readEnd)
                continue
            }

            let nsBlock = blockText as NSString
            let fullRange = NSRange(location: 0, length: nsBlock.length)
            let matches = regex.matches(in: blockText, range: fullRange)

            var seekPos = 0 // UTF-16 offset of text consumed so far in this block

            for match in matches {
                guard match.range.location != NSNotFound else { continue }

                let title = nsBlock.substring(with: match.range)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }

                let chapterStartUTF16 = match.range.location

                let precedingText = nsBlock.substring(
                    with: NSRange(location: seekPos, length: chapterStartUTF16 - seekPos)
                )
                let precedingByteLen = byteLength(of: precedingText, encoding: encoding)

                let matchByteOffset = curByteOffset + Int64(precedingByteLen)

                if !chapters.isEmpty {
                    let last = chapters.count - 1
                    chapters[last] = TXTChapter(
                        index: chapters[last].index,
                        title: chapters[last].title,
                        startByte: chapters[last].startByte,
                        endByte: matchByteOffset
                    )
                }

                chapters.append(TXTChapter(
                    index: chapters.count,
                    title: title,
                    startByte: matchByteOffset,
                    endByte: totalBytes
                ))

                seekPos = chapterStartUTF16 + match.range.length
            }

            curByteOffset = Int64(readEnd)
        }

        if let first = chapters.first, first.startByte > Int64(bomLength) {
            var updated = [TXTChapter(
                index: 0,
                title: "前言",
                startByte: Int64(bomLength),
                endByte: first.startByte
            )]
            for (i, ch) in chapters.enumerated() {
                updated.append(TXTChapter(
                    index: i + 1,
                    title: ch.title,
                    startByte: ch.startByte,
                    endByte: ch.endByte
                ))
            }
            chapters = updated
        }

        if !chapters.isEmpty {
            let last = chapters.count - 1
            chapters[last] = TXTChapter(
                index: chapters[last].index,
                title: chapters[last].title,
                startByte: chapters[last].startByte,
                endByte: totalBytes
            )
        }

        return chapters
    }

    static func byteLength(of string: String, encoding: String.Encoding) -> Int {
        string.data(using: encoding)?.count ?? string.utf8.count
    }
}

// MARK: - Synthetic Chapter Building

private extension TXTChapterIndexBuilder {

    /// Creates synthetic chapters at ~50KB byte boundaries, splitting at paragraph breaks.
    static func buildSynthetic(
        data: Data,
        bomLength: Int,
        totalBytes: Int64
    ) -> [TXTChapter] {
        let start = Int64(bomLength)
        let fileSize = Int(totalBytes) - bomLength

        if fileSize <= syntheticChapterSize {
            return [TXTChapter(
                index: 0,
                title: "Chapter 1",
                startByte: start,
                endByte: totalBytes
            )]
        }

        var chapters: [TXTChapter] = []
        var pos = Int(start)

        while pos < Int(totalBytes) {
            let targetEnd = min(pos + syntheticChapterSize, Int(totalBytes))

            if targetEnd >= Int(totalBytes) {
                chapters.append(TXTChapter(
                    index: chapters.count,
                    title: "Chapter \(chapters.count + 1)",
                    startByte: Int64(pos),
                    endByte: totalBytes
                ))
                break
            }

            let splitPos = findParagraphBreak(
                data: data,
                near: targetEnd,
                searchRange: 2000,
                floor: pos + 1
            )

            chapters.append(TXTChapter(
                index: chapters.count,
                title: "Chapter \(chapters.count + 1)",
                startByte: Int64(pos),
                endByte: Int64(splitPos)
            ))
            pos = splitPos
        }

        return chapters
    }
}

// MARK: - Helpers

private extension TXTChapterIndexBuilder {

    /// Detects BOM length at the start of data.
    static func detectBOMLength(data: Data) -> Int {
        guard data.count >= 2 else { return 0 }
        if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
            return 3
        }
        if (data[0] == 0xFE && data[1] == 0xFF) || (data[0] == 0xFF && data[1] == 0xFE) {
            return 2
        }
        return 0
    }

    /// Walks back from `from` to the last newline (0x0A), not below `floor`.
    static func walkBackToNewline(data: Data, from: Int, floor: Int) -> Int {
        var pos = from - 1
        while pos > floor {
            if data[pos] == 0x0A {
                return pos + 1
            }
            pos -= 1
        }
        return from
    }

    /// Finds a \n\n paragraph break near `target`, searching +/- `searchRange` bytes.
    static func findParagraphBreak(
        data: Data,
        near target: Int,
        searchRange: Int,
        floor: Int
    ) -> Int {
        let searchEnd = min(data.count - 1, target + searchRange)
        let searchStart = max(floor, target - searchRange)

        for i in target..<searchEnd {
            if data[i] == 0x0A && i + 1 < data.count && data[i + 1] == 0x0A {
                return i + 2
            }
        }

        var i = target - 1
        while i >= searchStart {
            if data[i] == 0x0A && i + 1 < data.count && data[i + 1] == 0x0A {
                return i + 2
            }
            i -= 1
        }

        return target
    }
}
