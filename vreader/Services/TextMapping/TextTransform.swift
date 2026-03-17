// Purpose: Protocol defining a text transformation that produces an OffsetMap
// for bidirectional offset mapping between source and display text.
//
// Key decisions:
// - Transforms are composable via TextMapper.
// - Each transform produces an OffsetMap tracking how offsets shift.
// - Protocol is Sendable for safe cross-actor use.
//
// @coordinates-with: OffsetMap.swift, TextMapper.swift

import Foundation

/// Result of applying a text transformation.
struct TransformResult: Sendable, Equatable {
    /// The transformed (display) text.
    let text: String
    /// Mapping from source offsets to display offsets.
    let offsetMap: OffsetMap
}

/// Protocol for text transformations that track offset changes.
protocol TextTransform: Sendable {
    /// Apply the transform to the given input text.
    /// Returns the transformed text and an offset map for bidirectional lookup.
    func transform(input: String) -> TransformResult
}
