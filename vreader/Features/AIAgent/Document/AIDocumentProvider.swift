// Purpose: Format-neutral document-provider contract for Feature #177 WI-3.
// Providers emit structured source chunks; flattened text is never location truth.

import Foundation

@MainActor
protocol AIDocumentProvider: AnyObject {
    var bookFingerprint: DocumentFingerprint { get }
    var format: BookFormat { get }

    func chunks() async throws -> [AIDocumentChunk]
    func snapshot() async throws -> AIDocumentSnapshot
}

enum AIDocumentProviderError: Error, Equatable, Sendable {
    case documentUnavailable
    case invalidCurrentLocation
}

extension AIDocumentProvider {
    var format: BookFormat { bookFingerprint.format }
}

enum AIDocumentChunkFactory {
    static func stableID(
        fingerprint: DocumentFingerprint,
        sourceUnitID: String,
        localStartUTF16: Int?
    ) -> String {
        "\(fingerprint.canonicalKey):\(sourceUnitID):\(localStartUTF16 ?? 0)"
    }

    static func emptyLocator(for fingerprint: DocumentFingerprint) -> Locator {
        Locator(
            bookFingerprint: fingerprint,
            href: nil,
            progression: nil,
            totalProgression: nil,
            cfi: nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: nil,
            textContextBefore: nil,
            textContextAfter: nil
        )
    }
}
