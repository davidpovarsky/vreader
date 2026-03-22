// Purpose: Minimal write-only ZIP archive creator using Foundation.
// Creates uncompressed (Stored) ZIP archives for backup data.
// Also provides extraction helpers for reading entries back.
//
// Key decisions:
// - Uses Stored (method 0) for simplicity and reliability.
//   JSON backup data compresses poorly relative to archive size,
//   and the upload channel (WebDAV) often handles compression.
// - CRC32 computed using the zlib crc32() function via Compression.
// - Matches ZIP format structures used by ZIPReader for round-trip compatibility.
// - Static methods only — no mutable state.
//
// @coordinates-with: ZIPReader.swift, WebDAVProvider.swift

import Foundation
import Compression

// MARK: - ZIPWriter

/// Creates ZIP archives in memory from named data entries.
enum ZIPWriter {

    /// A single file to include in the archive.
    struct Entry: Sendable {
        /// Relative path within the archive (e.g., "metadata.json").
        let name: String
        /// File contents.
        let data: Data
    }

    // MARK: - Archive Creation

    /// Creates a ZIP archive containing the given entries.
    ///
    /// Uses Stored (no compression) method for simplicity.
    /// The resulting Data can be written to disk or uploaded directly.
    ///
    /// - Parameter entries: Files to include in the archive.
    /// - Returns: Complete ZIP archive as Data.
    /// - Throws: If entry names cannot be encoded as UTF-8.
    static func createArchive(entries: [Entry]) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var localOffsets: [Int] = []

        for entry in entries {
            guard let nameData = entry.name.data(using: .utf8) else {
                throw ZIPWriterError.invalidEntryName(entry.name)
            }

            let crc = crc32Checksum(entry.data)
            let fileSize = UInt32(entry.data.count)
            let nameLength = UInt16(nameData.count)

            // Record offset for central directory
            localOffsets.append(archive.count)

            // --- Local File Header ---
            archive.appendUInt32LE(0x04034b50) // signature
            archive.appendUInt16LE(20)          // version needed (2.0)
            archive.appendUInt16LE(0)           // general purpose bit flag
            archive.appendUInt16LE(0)           // compression method (stored)
            archive.appendUInt16LE(0)           // last mod time
            archive.appendUInt16LE(0)           // last mod date
            archive.appendUInt32LE(crc)         // CRC-32
            archive.appendUInt32LE(fileSize)    // compressed size
            archive.appendUInt32LE(fileSize)    // uncompressed size
            archive.appendUInt16LE(nameLength)  // filename length
            archive.appendUInt16LE(0)           // extra field length
            archive.append(nameData)            // filename
            archive.append(entry.data)          // file data

            // --- Central Directory Entry ---
            centralDirectory.appendUInt32LE(0x02014b50) // signature
            centralDirectory.appendUInt16LE(20)          // version made by
            centralDirectory.appendUInt16LE(20)          // version needed
            centralDirectory.appendUInt16LE(0)           // general purpose bit flag
            centralDirectory.appendUInt16LE(0)           // compression method
            centralDirectory.appendUInt16LE(0)           // last mod time
            centralDirectory.appendUInt16LE(0)           // last mod date
            centralDirectory.appendUInt32LE(crc)         // CRC-32
            centralDirectory.appendUInt32LE(fileSize)    // compressed size
            centralDirectory.appendUInt32LE(fileSize)    // uncompressed size
            centralDirectory.appendUInt16LE(nameLength)  // filename length
            centralDirectory.appendUInt16LE(0)           // extra field length
            centralDirectory.appendUInt16LE(0)           // file comment length
            centralDirectory.appendUInt16LE(0)           // disk number start
            centralDirectory.appendUInt16LE(0)           // internal file attributes
            centralDirectory.appendUInt32LE(0)           // external file attributes
            centralDirectory.appendUInt32LE(UInt32(localOffsets.last!)) // offset
            centralDirectory.append(nameData)            // filename
        }

        let cdOffset = UInt32(archive.count)
        let cdSize = UInt32(centralDirectory.count)
        archive.append(centralDirectory)

        // --- End of Central Directory Record ---
        archive.appendUInt32LE(0x06054b50)          // signature
        archive.appendUInt16LE(0)                    // disk number
        archive.appendUInt16LE(0)                    // disk with CD
        archive.appendUInt16LE(UInt16(entries.count)) // entries on this disk
        archive.appendUInt16LE(UInt16(entries.count)) // total entries
        archive.appendUInt32LE(cdSize)               // CD size
        archive.appendUInt32LE(cdOffset)             // CD offset
        archive.appendUInt16LE(0)                    // comment length

        return archive
    }

    // MARK: - Extraction Helpers

    /// Lists all entry names in a ZIP archive.
    ///
    /// - Parameter data: Raw ZIP archive data.
    /// - Returns: Array of entry name strings.
    /// - Throws: If the archive is malformed.
    static func listEntryNames(in data: Data) throws -> [String] {
        let entries = try parseEntries(data)
        return entries.map(\.name)
    }

    /// Extracts a single entry's data from a ZIP archive.
    ///
    /// - Parameters:
    ///   - name: The entry name to extract.
    ///   - data: Raw ZIP archive data.
    /// - Returns: The uncompressed entry data.
    /// - Throws: If the entry is not found or archive is malformed.
    static func extractEntry(named name: String, from data: Data) throws -> Data {
        let entries = try parseEntries(data)
        guard let entry = entries.first(where: { $0.name == name }) else {
            throw ZIPWriterError.entryNotFound(name)
        }
        let start = entry.dataOffset
        let end = start + entry.dataSize
        guard end <= data.count else {
            throw ZIPWriterError.corruptArchive
        }
        return Data(data[start..<end])
    }

    // MARK: - Private Parsing

    /// Parsed entry info for extraction.
    private struct ParsedEntry {
        let name: String
        let dataOffset: Int
        let dataSize: Int
    }

    /// Parses central directory to find entries and their data offsets.
    private static func parseEntries(_ data: Data) throws -> [ParsedEntry] {
        guard let eocdOffset = findEOCD(in: data) else {
            throw ZIPWriterError.corruptArchive
        }

        let cdOffset = Int(readUInt32LE(data, at: eocdOffset + 16))
        let entryCount = Int(readUInt16LE(data, at: eocdOffset + 10))
        var entries: [ParsedEntry] = []
        var offset = cdOffset

        for _ in 0..<entryCount {
            guard offset + 46 <= data.count,
                  readUInt32LE(data, at: offset) == 0x02014b50 else {
                throw ZIPWriterError.corruptArchive
            }

            let fileSize = Int(readUInt32LE(data, at: offset + 20))
            let nameLength = Int(readUInt16LE(data, at: offset + 28))
            let extraLength = Int(readUInt16LE(data, at: offset + 30))
            let commentLength = Int(readUInt16LE(data, at: offset + 32))
            let localHeaderOffset = Int(readUInt32LE(data, at: offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else {
                throw ZIPWriterError.corruptArchive
            }
            let nameData = data[nameStart..<(nameStart + nameLength)]
            guard let name = String(data: Data(nameData), encoding: .utf8) else {
                throw ZIPWriterError.corruptArchive
            }

            // Parse local file header to get data offset
            guard localHeaderOffset + 30 <= data.count,
                  readUInt32LE(data, at: localHeaderOffset) == 0x04034b50 else {
                throw ZIPWriterError.corruptArchive
            }
            let localNameLen = Int(readUInt16LE(data, at: localHeaderOffset + 26))
            let localExtraLen = Int(readUInt16LE(data, at: localHeaderOffset + 28))
            let dataOffset = localHeaderOffset + 30 + localNameLen + localExtraLen

            entries.append(ParsedEntry(
                name: name,
                dataOffset: dataOffset,
                dataSize: fileSize
            ))

            offset += 46 + nameLength + extraLength + commentLength
        }

        return entries
    }

    /// Finds the End of Central Directory record.
    private static func findEOCD(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let maxSearch = min(data.count, 65536 + 22)
        let start = max(0, data.count - maxSearch)
        for i in stride(from: data.count - 22, through: start, by: -1) {
            if data[i] == 0x50 && data[i + 1] == 0x4B
                && data[i + 2] == 0x05 && data[i + 3] == 0x06 {
                return i
            }
        }
        return nil
    }

    // MARK: - CRC32

    /// Computes CRC32 checksum using zlib.
    private static func crc32Checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer -> UInt32 in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            var crc: UInt32 = 0
            crc = crc ^ 0xFFFFFFFF
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
            for i in 0..<data.count {
                let index = Int((crc ^ UInt32(bytes[i])) & 0xFF)
                crc = Self.crc32Table[index] ^ (crc >> 8)
            }
            return crc ^ 0xFFFFFFFF
        }
    }

    /// CRC32 lookup table (polynomial 0xEDB88320).
    private static let crc32Table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = 0xEDB88320 ^ (crc >> 1)
                } else {
                    crc = crc >> 1
                }
            }
            table[i] = crc
        }
        return table
    }()

    // MARK: - Binary Helpers

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
        | UInt32(data[offset + 1]) << 8
        | UInt32(data[offset + 2]) << 16
        | UInt32(data[offset + 3]) << 24
    }
}

// MARK: - ZIPWriterError

enum ZIPWriterError: Error, Sendable {
    case invalidEntryName(String)
    case entryNotFound(String)
    case corruptArchive
}

// MARK: - Data Helpers

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
