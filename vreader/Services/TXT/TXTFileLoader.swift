// Purpose: Loads and prepares a TXT file for reading — service open + position
// restore. Extracted from TXTReaderViewModel.open() in WI-008d to reduce VM size.
//
// Key decisions:
// - Pure function (enum namespace) — no state, no MainActor.
// - Throws original TXTServiceError without wrapping.
// - Position restore is non-fatal (falls back to offset 0).
// - Offset is clamped to text length to prevent out-of-bounds.
// - Checks Task.isCancelled between service open and position restore.
// - Reports whether a saved position was found (for restore-suppress logic).
//
// @coordinates-with: TXTReaderViewModel.swift, TXTServiceProtocol.swift,
//   ReadingPositionPersisting.swift

import Foundation

/// Result of loading a TXT file.
struct TXTLoadResult: Sendable {
    let metadata: TXTFileMetadata
    let restoredOffsetUTF16: Int
    /// Whether a saved position was found and restored (drives scroll-suppress).
    let hadSavedPosition: Bool
}

/// Loads a TXT file: opens via service and restores the saved reading position.
enum TXTFileLoader {

    /// Opens the file via the given service and restores the saved position.
    /// Throws the original service error on failure — no wrapping.
    static func load(
        url: URL,
        service: any TXTServiceProtocol,
        positionStore: any ReadingPositionPersisting,
        bookFingerprintKey: String
    ) async throws -> TXTLoadResult {
        // Stage 1: Open via service (throws on failure)
        let meta = try await service.open(url: url)

        // Early exit if cancelled — close service to avoid leak
        if Task.isCancelled {
            await service.close()
            throw CancellationError()
        }

        // Stage 2: Restore saved position (non-fatal)
        let (offset, hadSaved) = await restoreOffset(
            textLengthUTF16: meta.totalTextLengthUTF16,
            positionStore: positionStore,
            bookFingerprintKey: bookFingerprintKey
        )

        return TXTLoadResult(
            metadata: meta,
            restoredOffsetUTF16: offset,
            hadSavedPosition: hadSaved
        )
    }

    // MARK: - Private

    private static func restoreOffset(
        textLengthUTF16: Int,
        positionStore: any ReadingPositionPersisting,
        bookFingerprintKey: String
    ) async -> (offset: Int, hadSaved: Bool) {
        do {
            let savedLocator = try await positionStore.loadPosition(
                bookFingerprintKey: bookFingerprintKey
            )
            if let savedLocator, let savedOffset = savedLocator.charOffsetUTF16 {
                return (clamp(savedOffset, max: textLengthUTF16), true)
            }
        } catch {
            // Position restore failure is non-fatal — fall back to 0
        }
        return (0, false)
    }

    private static func clamp(_ offset: Int, max: Int) -> Int {
        min(Swift.max(offset, 0), max)
    }
}
