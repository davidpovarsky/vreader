// Purpose: Applies a sequence of TextTransforms to source text, building
// a composed OffsetMap for bidirectional offset conversion.
//
// Key decisions:
// - Transforms applied left-to-right (first transform runs first).
// - Composed OffsetMap chains all individual maps.
// - Empty transform list returns identity (source == display).
// - Thread-safe: all inputs/outputs are Sendable value types.
//
// @coordinates-with: TextTransform.swift, OffsetMap.swift,
//   ReflowableTextSource.swift

import Foundation

/// Applies a chain of text transforms and produces a final OffsetMap.
struct TextMapper: Sendable {

    /// Apply a sequence of transforms to source text.
    /// Returns the final display text and a composed OffsetMap
    /// mapping source offsets ↔ display offsets.
    static func apply(
        transforms: [any TextTransform],
        to sourceText: String
    ) -> TransformResult {
        guard !transforms.isEmpty else {
            let len = sourceText.utf16.count
            return TransformResult(
                text: sourceText,
                offsetMap: .identity(lengthUTF16: len)
            )
        }

        var currentText = sourceText
        var composedMap: OffsetMap? = nil

        for transform in transforms {
            let result = transform.transform(input: currentText)
            if let existing = composedMap {
                composedMap = existing.compose(with: result.offsetMap)
            } else {
                composedMap = result.offsetMap
            }
            currentText = result.text
        }

        return TransformResult(
            text: currentText,
            offsetMap: composedMap ?? .identity(lengthUTF16: sourceText.utf16.count)
        )
    }
}
