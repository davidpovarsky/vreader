// Purpose: Simplified/Traditional Chinese conversion using ICU transforms.
// Conforms to TextTransform protocol for offset-tracked conversion.
//
// Key decisions:
// - Uses CFStringTransform with kCFStringTransformSimplifiedToTraditional
//   and kCFStringTransformTraditionalToSimplified for OS-level conversion.
// - Builds OffsetMap by comparing source and result character-by-character.
// - CJK chars are 1:1 in UTF-16, so offset mapping is straightforward
//   for most cases. Multi-code-unit mappings are tracked if they occur.
// - Direction is an enum: .simpToTrad or .tradToSimp.
//
// @coordinates-with: TextTransform.swift, OffsetMap.swift,
//   SimpTradDictionary.swift, ReaderSettingsStore.swift

import Foundation

/// Direction of Chinese script conversion.
enum ChineseConversionDirection: String, Codable, Sendable {
    case simpToTrad
    case tradToSimp
    case none
}

/// Text transform for Simplified↔Traditional Chinese conversion
/// using ICU CFStringTransform.
struct SimpTradTransform: TextTransform {
    let direction: ChineseConversionDirection

    func transform(input: String) -> TransformResult {
        guard direction != .none, !input.isEmpty else {
            return TransformResult(
                text: input,
                offsetMap: .identity(lengthUTF16: input.utf16.count)
            )
        }

        let mutableString = NSMutableString(string: input)
        let transformName: CFString
        let reverse: Bool

        switch direction {
        case .simpToTrad:
            // kCFStringTransformMandarinLatin is NOT correct for simp/trad.
            // The correct ICU transform ID for Simplified → Traditional:
            transformName = "Hans-Hant" as CFString
            reverse = false
        case .tradToSimp:
            transformName = "Hans-Hant" as CFString
            reverse = true
        case .none:
            return TransformResult(
                text: input,
                offsetMap: .identity(lengthUTF16: input.utf16.count)
            )
        }

        let success = CFStringTransform(mutableString, nil, transformName, reverse)

        guard success else {
            // Fallback: return identity if transform fails
            return TransformResult(
                text: input,
                offsetMap: .identity(lengthUTF16: input.utf16.count)
            )
        }

        let output = mutableString as String
        let offsetMap = buildOffsetMap(source: input, display: output)

        return TransformResult(text: output, offsetMap: offsetMap)
    }

    // MARK: - Private

    /// Build an OffsetMap by comparing source and display character-by-character.
    /// For CJK Simplified↔Traditional, most chars are 1:1 in UTF-16.
    private func buildOffsetMap(source: String, display: String) -> OffsetMap {
        var entries: [OffsetEntry] = []
        var sourceOffset = 0
        var displayOffset = 0

        var sourceIter = source.makeIterator()
        var displayIter = display.makeIterator()

        while let sourceChar = sourceIter.next() {
            guard let displayChar = displayIter.next() else { break }

            let sourceCharLen = String(sourceChar).utf16.count
            let displayCharLen = String(displayChar).utf16.count

            if sourceChar != displayChar || sourceCharLen != displayCharLen {
                entries.append(OffsetEntry(
                    sourceOffset: sourceOffset,
                    displayOffset: displayOffset,
                    sourceLength: sourceCharLen,
                    displayLength: displayCharLen
                ))
            }

            sourceOffset += sourceCharLen
            displayOffset += displayCharLen
        }

        // Handle any remaining display chars (shouldn't happen for 1:1 conversions)
        while let displayChar = displayIter.next() {
            let displayCharLen = String(displayChar).utf16.count
            displayOffset += displayCharLen
        }

        return OffsetMap(
            entries: entries,
            sourceLengthUTF16: source.utf16.count,
            displayLengthUTF16: display.utf16.count
        )
    }
}
