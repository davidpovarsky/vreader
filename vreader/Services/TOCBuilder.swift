// Purpose: Format-specific TOC construction helpers.
// Builds flat TOCEntry lists from format-specific sources.
//
// Key decisions:
// - EPUB: builds from EPUBSpineItem titles (skips untitled items).
// - PDF: placeholder for outline tree traversal (not yet wired).
// - TXT: auto-detects chapter patterns using Legado-ported rules (25 patterns).
// - MD: extracts ATX headings (# through ######), skipping fenced code blocks.
//
// @coordinates-with: TOCProvider.swift, EPUBTypes.swift, LocatorFactory.swift, TXTTocRuleEngine.swift

import Foundation

/// Namespace for format-specific TOC construction.
enum TOCBuilder {

    // MARK: - EPUB

    /// Builds TOC entries from EPUB spine items.
    /// Spine items without titles are excluded.
    static func fromSpineItems(
        _ items: [EPUBSpineItem],
        fingerprint: DocumentFingerprint
    ) -> [TOCEntry] {
        items.enumerated().compactMap { index, item in
            guard let rawTitle = item.title,
                  !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            let locator = LocatorFactory.epub(
                fingerprint: fingerprint,
                href: item.href,
                progression: 0.0
            )

            guard let locator else { return nil }

            return TOCEntry(
                title: title,
                level: 0,
                locator: locator,
                sequenceIndex: index
            )
        }
    }

    // MARK: - PDF

    /// Builds TOC entries from PDF outline entries.
    /// Each entry provides a title, nesting level, and page index.
    static func fromPDFOutline(
        entries: [(title: String, level: Int, page: Int)],
        fingerprint: DocumentFingerprint
    ) -> [TOCEntry] {
        entries.enumerated().compactMap { index, entry in
            let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return nil }

            let locator = LocatorFactory.pdf(
                fingerprint: fingerprint,
                page: entry.page
            )

            guard let locator else { return nil }

            return TOCEntry(
                title: trimmedTitle,
                level: entry.level,
                locator: locator,
                sequenceIndex: index
            )
        }
    }

    // MARK: - TXT

    /// Auto-detects chapter patterns in TXT using Legado-ported regex rules.
    /// Falls back to empty array if no rule matches at least 2 times.
    static func forTXT(
        text: String,
        fingerprint: DocumentFingerprint
    ) -> [TOCEntry] {
        guard !text.isEmpty else { return [] }

        let rules = TXTTocRuleEngine.defaultRules
        guard let bestRule = TXTTocRuleEngine.detectBestRule(
            text: text, rules: rules
        ) else {
            return []
        }

        return TXTTocRuleEngine.extractTOC(
            text: text, rule: bestRule, fingerprint: fingerprint
        )
    }

    /// Legacy no-argument version for backward compatibility.
    static func forTXT() -> [TOCEntry] {
        []
    }

    // MARK: - MD

    /// Extracts ATX headings from Markdown text.
    /// Skips headings inside fenced code blocks (backtick or tilde fences).
    /// Returns entries in document order with level = (hash count - 1).
    static func forMD(
        text: String,
        fingerprint: DocumentFingerprint
    ) -> [TOCEntry] {
        guard !text.isEmpty else { return [] }

        let lines = text.components(separatedBy: "\n")
        var entries: [TOCEntry] = []
        var sequenceIndex = 0
        var utf16Offset = 0

        // Fenced code block tracking: stores the fence marker character
        // so inner fences with fewer backticks/tildes don't close it.
        var fenceChar: Character?
        var fenceLength: Int = 0

        for (lineIndex, line) in lines.enumerated() {
            // Advance offset past this line after processing.
            // Each line contributes its UTF-16 length + 1 for the \n separator,
            // except the last line which has no trailing newline.
            defer {
                utf16Offset += line.utf16.count + (lineIndex < lines.count - 1 ? 1 : 0)
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for fence open/close
            if let (char, length) = parseFenceLine(trimmed) {
                if fenceChar == nil {
                    // Open a fence
                    fenceChar = char
                    fenceLength = length
                } else if char == fenceChar, length >= fenceLength {
                    // Close the fence
                    fenceChar = nil
                    fenceLength = 0
                }
                continue
            }

            // Skip lines inside fenced code blocks
            if fenceChar != nil { continue }

            // Match ATX heading
            guard let (level, title) = parseATXHeading(trimmed) else { continue }

            let locator = LocatorFactory.mdPosition(
                fingerprint: fingerprint,
                charOffsetUTF16: utf16Offset
            )
            guard let locator else { continue }

            entries.append(TOCEntry(
                title: title,
                level: level,
                locator: locator,
                sequenceIndex: sequenceIndex
            ))
            sequenceIndex += 1
        }

        return entries
    }

    // MARK: - MD Private Helpers

    /// Parses a line as a fenced code block delimiter.
    /// Returns the fence character and its count, or nil if not a fence line.
    private static func parseFenceLine(_ trimmed: String) -> (Character, Int)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        // Fence lines may have an info string after backticks, but no backticks in it
        if first == "`" {
            let rest = trimmed.dropFirst(count)
            if rest.contains("`") { return nil }
        }
        return (first, count)
    }

    /// Parses an ATX heading line. Returns (level, title) or nil.
    /// Level is 0-based (# = 0, ## = 1, ..., ###### = 5).
    private static func parseATXHeading(_ trimmed: String) -> (Int, String)? {
        guard trimmed.hasPrefix("#") else { return nil }

        let hashCount = trimmed.prefix(while: { $0 == "#" }).count
        guard hashCount >= 1, hashCount <= 6 else { return nil }

        // Must have a space after the hashes
        let afterHashes = trimmed.dropFirst(hashCount)
        guard afterHashes.hasPrefix(" ") else { return nil }

        // Extract title, stripping trailing closing hashes per CommonMark
        var title = String(afterHashes).trimmingCharacters(in: .whitespaces)
        // Strip optional trailing ATX closing sequence: one or more trailing #
        // (optionally preceded by spaces)
        if title.hasSuffix("#") {
            let stripped = title
                .reversed()
                .drop(while: { $0 == "#" })
                .reversed()
            let beforeHashes = String(stripped).trimmingCharacters(in: .whitespaces)
            if !beforeHashes.isEmpty {
                title = beforeHashes
            }
        }

        guard !title.isEmpty else { return nil }
        return (hashCount - 1, title)
    }
}
