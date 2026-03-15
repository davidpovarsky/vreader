// Purpose: Pure formatting function for file sizes in bytes.
// Uses Foundation's ByteCountFormatter for locale-aware display.
//
// Key decisions:
// - Zero and negative byte counts return "Unknown" or "Zero KB".
// - Uses ByteCountFormatter with file count style for standard output.
//
// @coordinates-with: BookInfoSheet.swift, LibraryBookItem.swift

import Foundation

/// Formatting utility for file sizes.
enum FileSizeFormatter {

    /// Formats a byte count into a human-readable string.
    ///
    /// Examples:
    /// - 0 -> "Zero KB"
    /// - -100 -> "Zero KB"
    /// - 500 -> "500 bytes"
    /// - 1024 -> "1 KB"
    /// - 2_516_582 -> "2.4 MB"
    /// - 1_073_741_824 -> "1 GB"
    static func format(byteCount: Int64) -> String {
        guard byteCount > 0 else { return "Zero KB" }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: byteCount)
    }
}
