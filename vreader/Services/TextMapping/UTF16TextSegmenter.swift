// Purpose: Shared paragraph segmentation with exact UTF-16 source ranges.
// TXT search and Feature #177 document mapping consume the same coordinate
// contract, including CRLF and surrogate-pair-safe offsets.

import Foundation

struct UTF16TextSegment: Sendable, Equatable {
    let index: Int
    let text: String
    let startUTF16: Int
    let endUTF16: Int
}

enum UTF16TextSegmenter {
    static func segments(in text: String) -> [UTF16TextSegment] {
        guard !text.isEmpty else { return [] }

        let paragraphSeparators = ranges(
            matching: "(?:\\r\\n|\\n|\\r){2,}",
            in: text
        )
        let paragraphParts = parts(in: text, separatedBy: paragraphSeparators)
        let nonEmptyParagraphCount = paragraphParts.filter(isNonEmpty).count

        if nonEmptyParagraphCount <= 1 && text.count > 500 {
            return makeSegments(
                in: text,
                separators: ranges(matching: "\\r\\n|\\n|\\r", in: text)
            )
        }
        return makeSegments(in: text, separators: paragraphSeparators)
    }

    private static func makeSegments(
        in text: String,
        separators: [NSRange]
    ) -> [UTF16TextSegment] {
        let nsText = text as NSString
        let fullLength = nsText.length
        var cursor = 0
        var result: [UTF16TextSegment] = []

        for separator in separators {
            appendSegment(
                from: NSRange(location: cursor, length: separator.location - cursor),
                nsText: nsText,
                to: &result
            )
            cursor = NSMaxRange(separator)
        }
        appendSegment(
            from: NSRange(location: cursor, length: fullLength - cursor),
            nsText: nsText,
            to: &result
        )
        return result
    }

    private static func appendSegment(
        from range: NSRange,
        nsText: NSString,
        to result: inout [UTF16TextSegment]
    ) {
        let value = nsText.substring(with: range)
        guard isNonEmpty(value) else { return }
        result.append(UTF16TextSegment(
            index: result.count,
            text: value,
            startUTF16: range.location,
            endUTF16: NSMaxRange(range)
        ))
    }

    private static func parts(
        in text: String,
        separatedBy ranges: [NSRange]
    ) -> [String] {
        let nsText = text as NSString
        var cursor = 0
        var result: [String] = []
        for range in ranges {
            result.append(nsText.substring(with: NSRange(
                location: cursor,
                length: range.location - cursor
            )))
            cursor = NSMaxRange(range)
        }
        result.append(nsText.substring(from: cursor))
        return result
    }

    private static func ranges(matching pattern: String, in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, range: fullRange).map(\.range)
    }

    private static func isNonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
