// Purpose: Loads and prepares an EPUB for reading — parse + position restore.
// Extracted from EPUBReaderViewModel.open() in WI-008b to reduce VM size.
//
// Key decisions:
// - Pure function (enum namespace) — no state, no MainActor.
// - Throws original EPUBParser errors without wrapping.
// - Position restore is non-fatal (falls back to first spine item).
// - Checks Task.isCancelled between parse and position restore.
//
// @coordinates-with: EPUBReaderViewModel.swift, EPUBParserProtocol.swift,
//   ReadingPositionPersisting.swift

import Foundation

/// Result of loading an EPUB file.
struct EPUBLoadResult: Sendable {
    let metadata: EPUBMetadata
    let initialPosition: EPUBPosition?
}

/// Loads an EPUB file: parses metadata and restores the saved reading position.
enum EPUBFileLoader {

    /// Parses the EPUB and restores the saved position.
    /// Throws the original parser error on failure — no wrapping.
    static func load(
        url: URL,
        parser: any EPUBParserProtocol,
        positionStore: any ReadingPositionPersisting,
        bookFingerprintKey: String
    ) async throws -> EPUBLoadResult {
        // Stage 1: Parse EPUB (throws on failure)
        let meta = try await parser.open(url: url)

        // Early exit if cancelled between parse and restore — close parser to avoid leak
        if Task.isCancelled {
            await parser.close()
            throw CancellationError()
        }

        // Stage 2: Restore saved position (non-fatal)
        let position = await restorePosition(
            metadata: meta,
            positionStore: positionStore,
            bookFingerprintKey: bookFingerprintKey
        )

        return EPUBLoadResult(metadata: meta, initialPosition: position)
    }

    // MARK: - Private

    private static func restorePosition(
        metadata: EPUBMetadata,
        positionStore: any ReadingPositionPersisting,
        bookFingerprintKey: String
    ) async -> EPUBPosition? {
        do {
            let savedLocator = try await positionStore.loadPosition(
                bookFingerprintKey: bookFingerprintKey
            )
            if let savedLocator,
               let href = savedLocator.href,
               metadata.spineItems.contains(where: { $0.href == href }) {
                return EPUBPosition(
                    href: href,
                    progression: savedLocator.progression ?? 0,
                    totalProgression: savedLocator.totalProgression ?? 0,
                    cfi: savedLocator.cfi
                )
            }
        } catch {
            // Position restore failure is non-fatal — fall back to first spine
        }

        // Default: first spine item or nil for empty EPUBs
        guard let firstSpine = metadata.spineItems.first else { return nil }
        return EPUBPosition(
            href: firstSpine.href,
            progression: 0,
            totalProgression: 0,
            cfi: nil
        )
    }
}
