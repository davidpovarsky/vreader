// Purpose: Cross-mode locator/anchor normalization.
// Converts format-specific Locator to format-independent CanonicalPosition and back.
//
// Key decisions:
// - Uses totalProgression (0-1) as the format-independent position.
// - Preserves the original nativeLocator for lossless round-trip.
// - Pure functions, no side effects, no stored data modification.
// - textQuote + context preserved for fuzzy re-anchoring after content changes.
//
// @coordinates-with Locator.swift, AnnotationAnchor.swift, LocatorFactory.swift

import Foundation

/// Format-independent canonical reading position.
/// Wraps a 0-1 progression with the original native locator for lossless round-trip.
struct CanonicalPosition: Codable, Sendable, Equatable {
    /// Format-independent position: 0.0 (start) to 1.0 (end).
    let progression: Double

    /// Original format-specific locator, preserved for round-trip fidelity.
    let nativeLocator: Locator

    /// Selected or nearby text for fuzzy re-anchoring.
    let textQuote: String?

    /// Text before the quote for disambiguation.
    let textContextBefore: String?

    /// Text after the quote for disambiguation.
    let textContextAfter: String?
}

/// Stateless normalizer for converting between format-specific and canonical positions.
enum LocatorNormalizer {

    // MARK: - To Canonical

    /// Converts a format-specific Locator to a CanonicalPosition.
    ///
    /// The canonical progression is taken from `totalProgression` (already 0-1).
    /// If `totalProgression` is nil, falls back to 0.0.
    /// Progression is clamped to [0.0, 1.0].
    ///
    /// - Parameters:
    ///   - locator: The format-specific locator to normalize.
    ///   - format: The book format (used for documentation/future extensions).
    /// - Returns: A CanonicalPosition with the normalized progression.
    static func toCanonical(_ locator: Locator, format: BookFormat) -> CanonicalPosition {
        let rawProgression = locator.totalProgression ?? 0.0
        let clampedProgression = min(max(rawProgression, 0.0), 1.0)

        return CanonicalPosition(
            progression: clampedProgression,
            nativeLocator: locator,
            textQuote: locator.textQuote,
            textContextBefore: locator.textContextBefore,
            textContextAfter: locator.textContextAfter
        )
    }

    // MARK: - From Canonical

    /// Converts a CanonicalPosition back to a format-specific Locator.
    ///
    /// For lossless round-trip, the nativeLocator is returned directly.
    /// This preserves all format-specific fields (href, cfi, page, offsets, etc.).
    ///
    /// - Parameters:
    ///   - canonical: The canonical position to denormalize.
    ///   - format: The target format (used for documentation/future extensions).
    ///   - totalLengthUTF16: For TXT/MD, the total document length in UTF-16 code units.
    ///     Used for offset reconstruction if needed in future cross-format scenarios.
    /// - Returns: The format-specific Locator.
    static func fromCanonical(
        _ canonical: CanonicalPosition,
        toFormat format: BookFormat,
        totalLengthUTF16: Int?
    ) -> Locator {
        canonical.nativeLocator
    }
}
