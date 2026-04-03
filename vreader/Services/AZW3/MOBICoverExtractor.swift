// Purpose: Extracts cover images from MOBI/AZW3 files by parsing the PDB/MOBI
// binary format natively. Reads PDB header, record table, MOBI header, and EXTH
// records to locate the cover image data without needing WKWebView or Foliate-js.
//
// Key decisions:
// - All integers are big-endian (network byte order) per MOBI spec.
// - Returns nil on any failure (truncated file, missing EXTH, invalid offsets,
//   corrupt image data, DRM). Never crashes.
// - 0xFFFFFFFF means "not set" for coverOffset/thumbnailOffset.
// - Prefers coverOffset (type 201) over thumbnailOffset (type 202).
//
// @coordinates-with: MetadataExtractor.swift, BookImporter.swift

import UIKit

enum MOBICoverExtractor {

    /// Sentinel value meaning "not set" in MOBI/EXTH fields.
    private static let notSet: UInt32 = 0xFFFF_FFFF

    /// Minimum PDB header size (78 bytes).
    private static let pdbHeaderSize = 78

    /// Each record table entry is 8 bytes (4-byte offset + 4-byte attributes).
    private static let recordEntrySize = 8

    /// Extracts cover image from a MOBI/AZW3 file. Returns nil on any failure.
    static func extractCover(from fileURL: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              data.count >= pdbHeaderSize else {
            return nil
        }

        // 1. Parse PDB header → numRecords
        let numRecords = Int(readUInt16BE(data, offset: 76))
        guard numRecords > 0 else { return nil }

        let recordTableEnd = pdbHeaderSize + numRecords * recordEntrySize
        guard data.count >= recordTableEnd else { return nil }

        // 2. Build record offset table
        let recordOffsets = parseRecordOffsets(data: data, numRecords: numRecords)

        // 3. Read record 0
        guard let record0 = extractRecord(data: data, offsets: recordOffsets, index: 0) else {
            return nil
        }

        // 4. Parse MOBI header from record 0
        //    PalmDOC header = bytes 0..15 (16 bytes)
        //    MOBI header starts at byte 16
        //    Need at least 132 bytes (16 + 116 for exthFlag at offset 112 relative to MOBI start)
        guard record0.count >= 132 else { return nil }

        // Verify MOBI magic at offset 16
        let mobiMagic = String(data: record0[16..<20], encoding: .ascii)
        guard mobiMagic == "MOBI" else { return nil }

        // MOBI header length (at offset 20, i.e., 4 bytes after MOBI magic)
        let mobiLength = readUInt32BE(record0, offset: 20)

        // resourceStart = firstImageRecord at offset 108 (16 + 92)
        let firstImageRecord = Int(readUInt32BE(record0, offset: 108))

        // exthFlag at offset 128 (16 + 112)
        let exthFlag = readUInt32BE(record0, offset: 128)
        let hasEXTH = (exthFlag & 0x40) != 0
        guard hasEXTH else { return nil }

        // 5. Parse EXTH header
        //    EXTH starts right after MOBI header: offset = 16 + mobiLength
        let exthStart = 16 + Int(mobiLength)
        guard exthStart + 12 <= record0.count else { return nil }

        let exthMagic = String(data: record0[exthStart..<(exthStart + 4)], encoding: .ascii)
        guard exthMagic == "EXTH" else { return nil }

        let exthLength = Int(readUInt32BE(record0, offset: exthStart + 4))
        let exthRecordCount = Int(readUInt32BE(record0, offset: exthStart + 8))

        guard exthStart + exthLength <= record0.count else { return nil }

        // 6. Scan EXTH records for type 201 (coverOffset) and 202 (thumbnailOffset)
        var coverOffset: UInt32?
        var thumbnailOffset: UInt32?
        var cursor = exthStart + 12

        for _ in 0..<exthRecordCount {
            guard cursor + 8 <= record0.count else { break }
            let recType = readUInt32BE(record0, offset: cursor)
            let recLength = Int(readUInt32BE(record0, offset: cursor + 4))
            guard recLength >= 8, cursor + recLength <= record0.count else { break }

            if recType == 201, recLength == 12 {
                coverOffset = readUInt32BE(record0, offset: cursor + 8)
            } else if recType == 202, recLength == 12 {
                thumbnailOffset = readUInt32BE(record0, offset: cursor + 8)
            }
            cursor += recLength
        }

        // 7. Determine target image index (prefer cover over thumbnail)
        let imageRelativeIndex: UInt32
        if let co = coverOffset, co < notSet {
            imageRelativeIndex = co
        } else if let to = thumbnailOffset, to < notSet {
            imageRelativeIndex = to
        } else {
            return nil
        }

        let targetRecordIndex = firstImageRecord + Int(imageRelativeIndex)

        // 8. Extract image data from target record
        guard let imageData = extractRecord(
            data: data,
            offsets: recordOffsets,
            index: targetRecordIndex
        ) else {
            return nil
        }

        return UIImage(data: imageData)
    }

    // MARK: - Binary Helpers

    /// Reads a big-endian UInt16 from data at the given byte offset.
    private static func readUInt16BE(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    /// Reads a big-endian UInt32 from data at the given byte offset.
    private static func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }

    /// Parses the PDB record offset table into an array of byte offsets.
    private static func parseRecordOffsets(data: Data, numRecords: Int) -> [Int] {
        (0..<numRecords).map { i in
            let entryOffset = pdbHeaderSize + i * recordEntrySize
            return Int(readUInt32BE(data, offset: entryOffset))
        }
    }

    /// Extracts the data for a record at the given index.
    /// The record spans from its offset to the next record's offset (or EOF).
    /// Returns a fresh Data with 0-based indices (not a slice).
    private static func extractRecord(data: Data, offsets: [Int], index: Int) -> Data? {
        guard index >= 0, index < offsets.count else { return nil }
        let start = offsets[index]
        let end = (index + 1 < offsets.count) ? offsets[index + 1] : data.count
        guard start >= 0, end > start, end <= data.count else { return nil }
        return Data(data[start..<end])
    }
}
