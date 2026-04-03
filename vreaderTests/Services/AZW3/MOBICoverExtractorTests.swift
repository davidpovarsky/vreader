// Purpose: Tests for MOBICoverExtractor — native MOBI/PDB binary parsing for
// AZW3 cover image extraction. All test fixtures are built programmatically
// from binary data to avoid shipping actual book files.
//
// @coordinates-with: MOBICoverExtractor.swift

import Testing
import Foundation
import UIKit
@testable import vreader

// MARK: - Test Fixture Builder

/// Builds minimal valid MOBI binary data for testing.
/// Constructs PDB header + record table + record 0 (PalmDOC + MOBI + EXTH) + image record.
private enum MOBIFixture {

    // Minimal 1x1 red JPEG — smallest valid JPEG file.
    // Generated from: https://www.freeformatter.com/mime-types-list.html
    static let tinyJPEG: Data = {
        // A valid 1x1 JPEG (approximately 631 bytes, but we can use a truly minimal one)
        // This is a hand-crafted minimal JFIF JPEG:
        var d = Data()
        // SOI
        d.append(contentsOf: [0xFF, 0xD8])
        // APP0 (JFIF)
        d.append(contentsOf: [0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46,
                               0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01,
                               0x00, 0x00])
        // DQT
        d.append(contentsOf: [0xFF, 0xDB, 0x00, 0x43, 0x00])
        d.append(contentsOf: [UInt8](repeating: 0x01, count: 64))
        // SOF0 (1x1, 1 component)
        d.append(contentsOf: [0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00,
                               0x01, 0x01, 0x01, 0x11, 0x00])
        // DHT (DC table)
        d.append(contentsOf: [0xFF, 0xC4, 0x00, 0x1F, 0x00,
                               0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01,
                               0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                               0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                               0x08, 0x09, 0x0A, 0x0B])
        // DHT (AC table)
        d.append(contentsOf: [0xFF, 0xC4, 0x00, 0xB5, 0x10,
                               0x00, 0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03,
                               0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D])
        d.append(contentsOf: [UInt8](repeating: 0x00, count: 162 - 16))
        // SOS
        d.append(contentsOf: [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00,
                               0x3F, 0x00, 0x7B, 0x40])
        // Scan data (minimal)
        d.append(contentsOf: [0x00])
        // EOI
        d.append(contentsOf: [0xFF, 0xD9])
        return d
    }()

    /// Creates a minimal valid 1x1 PNG image data (much simpler than JPEG).
    static let tinyPNG: Data = {
        // Use UIKit to generate a known-good 1x1 image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return image.pngData()!
    }()

    /// Writes a big-endian UInt32 at the specified offset in data.
    static func writeUInt32BE(_ value: UInt32, to data: inout Data, at offset: Int) {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        for (i, b) in bytes.enumerated() {
            data[offset + i] = b
        }
    }

    /// Writes a big-endian UInt16 at the specified offset in data.
    static func writeUInt16BE(_ value: UInt16, to data: inout Data, at offset: Int) {
        data[offset] = UInt8((value >> 8) & 0xFF)
        data[offset + 1] = UInt8(value & 0xFF)
    }

    /// Builds a complete MOBI file with PDB header, record table, MOBI header
    /// with EXTH, and an image record containing the given image data.
    ///
    /// - Parameters:
    ///   - imageData: Raw image bytes for the cover record.
    ///   - coverOffset: EXTH type 201 value (index relative to firstImageRecord).
    ///     Use nil to omit coverOffset from EXTH.
    ///   - thumbnailOffset: EXTH type 202 value. Use nil to omit.
    ///   - hasEXTH: Whether to set the EXTH flag in MOBI header. Default true.
    ///   - extraRecordsBefore: Number of dummy records to insert between record 0 and image.
    /// - Returns: Complete binary data representing a minimal MOBI file.
    static func buildMOBI(
        imageData: Data = tinyPNG,
        coverOffset: UInt32? = 0,
        thumbnailOffset: UInt32? = nil,
        hasEXTH: Bool = true,
        extraRecordsBefore: Int = 0
    ) -> Data {
        // --- Build EXTH header ---
        var exthRecords = Data()
        var exthCount: UInt32 = 0

        if let co = coverOffset {
            // Type 201 = coverOffset
            var rec = Data(count: 12)
            writeUInt32BE(201, to: &rec, at: 0)        // type
            writeUInt32BE(12, to: &rec, at: 4)          // length (8 + 4 bytes data)
            writeUInt32BE(co, to: &rec, at: 8)           // value
            exthRecords.append(rec)
            exthCount += 1
        }
        if let to = thumbnailOffset {
            // Type 202 = thumbnailOffset
            var rec = Data(count: 12)
            writeUInt32BE(202, to: &rec, at: 0)
            writeUInt32BE(12, to: &rec, at: 4)
            writeUInt32BE(to, to: &rec, at: 8)
            exthRecords.append(rec)
            exthCount += 1
        }

        var exthHeader = Data()
        if hasEXTH {
            // "EXTH" magic + length + count + records
            exthHeader.append(contentsOf: [0x45, 0x58, 0x54, 0x48])  // "EXTH"
            var lengthAndCount = Data(count: 8)
            let exthLen = UInt32(12 + exthRecords.count)  // 4 magic + 4 length + 4 count + records
            writeUInt32BE(exthLen, to: &lengthAndCount, at: 0)
            writeUInt32BE(exthCount, to: &lengthAndCount, at: 4)
            exthHeader.append(lengthAndCount)
            exthHeader.append(exthRecords)
        }

        // --- Build Record 0 (PalmDOC + MOBI header + EXTH) ---
        // PalmDOC header: 16 bytes
        var palmDOC = Data(count: 16)
        writeUInt16BE(1, to: &palmDOC, at: 0)   // compression = none
        writeUInt16BE(0, to: &palmDOC, at: 8)   // numTextRecords = 0
        writeUInt16BE(4096, to: &palmDOC, at: 10) // recordSize
        writeUInt16BE(0, to: &palmDOC, at: 12)  // encryption = none

        // MOBI header: starts at offset 16 in record 0
        // We need at minimum up to offset 128+4 = 132 from start of record
        // MOBI header proper starts at offset 16; its internal offsets are relative to offset 16
        let mobiHeaderLength: UInt32 = 232  // standard MOBI header length (offset 20-23 = length)
        var mobiHeader = Data(count: Int(mobiHeaderLength))

        // MOBI magic at record offset 16 → mobiHeader[0..3]
        mobiHeader[0] = 0x4D  // M
        mobiHeader[1] = 0x4F  // O
        mobiHeader[2] = 0x42  // B
        mobiHeader[3] = 0x49  // I

        // header length at mobiHeader[4..7] (offset 20 in record)
        writeUInt32BE(mobiHeaderLength, to: &mobiHeader, at: 4)

        // encoding at mobiHeader[12..15] = 65001 (UTF-8)
        writeUInt32BE(65001, to: &mobiHeader, at: 12)

        // version at mobiHeader[20..23] = 6 (MOBI6)
        writeUInt32BE(6, to: &mobiHeader, at: 20)

        // firstImageRecord (resourceStart) at mobiHeader[92..95] = record offset 108
        // = firstImageRecord index in PDB record table
        let firstImageRecord = UInt32(1 + extraRecordsBefore)
        writeUInt32BE(firstImageRecord, to: &mobiHeader, at: 92)

        // exthFlag at mobiHeader[112..115] = record offset 128
        let exthFlag: UInt32 = hasEXTH ? 0x40 : 0x00  // bit 6
        writeUInt32BE(exthFlag, to: &mobiHeader, at: 112)

        // Build record 0 data
        var record0 = palmDOC
        record0.append(mobiHeader)
        if hasEXTH {
            record0.append(exthHeader)
        }

        // --- Build dummy records ---
        let dummyRecord = Data(repeating: 0x00, count: 4)

        // --- Calculate offsets for PDB header ---
        // numRecords = 1 (record 0) + extraRecordsBefore + 1 (image record)
        let numRecords = UInt16(1 + extraRecordsBefore + (imageData.isEmpty ? 0 : 1))
        let recordTableSize = Int(numRecords) * 8
        let dataStart = 78 + recordTableSize

        // Record offsets
        var currentOffset = dataStart
        var recordOffsets: [UInt32] = []

        // Record 0
        recordOffsets.append(UInt32(currentOffset))
        currentOffset += record0.count

        // Dummy records
        for _ in 0..<extraRecordsBefore {
            recordOffsets.append(UInt32(currentOffset))
            currentOffset += dummyRecord.count
        }

        // Image record
        if !imageData.isEmpty {
            recordOffsets.append(UInt32(currentOffset))
        }

        // --- Build PDB header (78 bytes) ---
        var pdbHeader = Data(count: 78)
        // name: "Test\0" at offset 0 (32 bytes, zero-padded)
        let nameBytes: [UInt8] = [0x54, 0x65, 0x73, 0x74]  // "Test"
        for (i, b) in nameBytes.enumerated() { pdbHeader[i] = b }

        // type: "BOOK" at offset 60
        pdbHeader[60] = 0x42; pdbHeader[61] = 0x4F; pdbHeader[62] = 0x4F; pdbHeader[63] = 0x4B
        // creator: "MOBI" at offset 64
        pdbHeader[64] = 0x4D; pdbHeader[65] = 0x4F; pdbHeader[66] = 0x42; pdbHeader[67] = 0x49

        // numRecords at offset 76
        writeUInt16BE(numRecords, to: &pdbHeader, at: 76)

        // --- Build record table ---
        var recordTable = Data(count: recordTableSize)
        for (i, offset) in recordOffsets.enumerated() {
            writeUInt32BE(offset, to: &recordTable, at: i * 8)
            // attributes + uniqueID (4 bytes) = 0
        }

        // --- Assemble file ---
        var fileData = pdbHeader
        fileData.append(recordTable)
        fileData.append(record0)
        for _ in 0..<extraRecordsBefore {
            fileData.append(dummyRecord)
        }
        if !imageData.isEmpty {
            fileData.append(imageData)
        }

        return fileData
    }

    /// Writes data to a temporary file and returns the URL.
    static func writeTempFile(_ data: Data, ext: String = "azw3") throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: tmp)
        return tmp
    }
}

// MARK: - Tests

@Suite("MOBICoverExtractor")
struct MOBICoverExtractorTests {

    // MARK: - Happy Path

    @Test("Valid AZW3 with EXTH coverOffset extracts UIImage")
    func validCoverOffset() throws {
        let data = MOBIFixture.buildMOBI(
            imageData: MOBIFixture.tinyPNG,
            coverOffset: 0
        )
        let url = try MOBIFixture.writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = MOBICoverExtractor.extractCover(from: url)
        #expect(image != nil, "Should extract a valid UIImage from cover record")
    }

    @Test("Valid AZW3 with thumbnailOffset (no coverOffset) extracts UIImage")
    func validThumbnailOffset() throws {
        let data = MOBIFixture.buildMOBI(
            imageData: MOBIFixture.tinyPNG,
            coverOffset: nil,
            thumbnailOffset: 0
        )
        let url = try MOBIFixture.writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = MOBICoverExtractor.extractCover(from: url)
        #expect(image != nil, "Should fall back to thumbnail when coverOffset absent")
    }

    @Test("Prefers coverOffset over thumbnailOffset")
    func prefersCoverOverThumbnail() throws {
        // coverOffset=0 → image record, thumbnailOffset=0xFFFFFFFF → invalid
        let data = MOBIFixture.buildMOBI(
            imageData: MOBIFixture.tinyPNG,
            coverOffset: 0,
            thumbnailOffset: 0xFFFF_FFFF
        )
        let url = try MOBIFixture.writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = MOBICoverExtractor.extractCover(from: url)
        #expect(image != nil, "Should use coverOffset even if thumbnailOffset is invalid")
    }

    // MARK: - No EXTH

    @Test("File without EXTH flag returns nil")
    func noEXTHFlag() throws {
        let data = MOBIFixture.buildMOBI(
            imageData: MOBIFixture.tinyPNG,
            coverOffset: 0,
            hasEXTH: false
        )
        let url = try MOBIFixture.writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = MOBICoverExtractor.extractCover(from: url)
        #expect(image == nil, "Should return nil when EXTH flag not set")
    }

    // MARK: - Invalid Offsets

    @Test("coverOffset 0xFFFFFFFF returns nil when no thumbnail")
    func coverOffsetNotSet() throws {
        let data = MOBIFixture.buildMOBI(
            imageData: MOBIFixture.tinyPNG,
            coverOffset: 0xFFFF_FFFF,
            thumbnailOffset: nil
        )
        let url = try MOBIFixture.writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = MOBICoverExtractor.extractCover(from: url)
        #expect(image == nil, "0xFFFFFFFF means 'not set'")
    }

    @Test("Both coverOffset and thumbnailOffset 0xFFFFFFFF returns nil")
    func bothOffsetsNotSet() throws {
        let data = MOBIFixture.buildMOBI(
            imageData: MOBIFixture.tinyPNG,
            coverOffset: 0xFFFF_FFFF,
            thumbnailOffset: 0xFFFF_FFFF
        )
        let url = try MOBIFixture.writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = MOBICoverExtractor.extractCover(from: url)
        #expect(image == nil, "Both not-set means no cover available")
    }

    // MARK: - Truncated / Corrupt Files

    @Test("Truncated file (too short for PDB header) returns nil")
    func truncatedFile() throws {
        let data = Data(repeating: 0x00, count: 50)  // < 78 bytes
        let url = try MOBIFixture.writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = MOBICoverExtractor.extractCover(from: url)
        #expect(image == nil, "Should handle truncated PDB header gracefully")
    }

    @Test("Empty file returns nil")
    func emptyFile() throws {
        let data = Data()
        let url = try MOBIFixture.writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = MOBICoverExtractor.extractCover(from: url)
        #expect(image == nil, "Should handle empty file gracefully")
    }

    @Test("Record index out of bounds returns nil")
    func recordIndexOutOfBounds() throws {
        // coverOffset=99 but only 1 image record exists
        let data = MOBIFixture.buildMOBI(
            imageData: MOBIFixture.tinyPNG,
            coverOffset: 99
        )
        let url = try MOBIFixture.writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = MOBICoverExtractor.extractCover(from: url)
        #expect(image == nil, "Should return nil when target record exceeds numRecords")
    }

    @Test("Corrupt image data in record returns nil")
    func corruptImageData() throws {
        let garbage = Data(repeating: 0xAB, count: 100)
        let data = MOBIFixture.buildMOBI(
            imageData: garbage,
            coverOffset: 0
        )
        let url = try MOBIFixture.writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = MOBICoverExtractor.extractCover(from: url)
        #expect(image == nil, "Should return nil for non-image data")
    }

    @Test("File that does not exist returns nil")
    func nonexistentFile() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).azw3")
        let image = MOBICoverExtractor.extractCover(from: url)
        #expect(image == nil)
    }

    // MARK: - Extra records between record 0 and image

    @Test("Cover with extra records before image record")
    func extraRecordsBeforeImage() throws {
        let data = MOBIFixture.buildMOBI(
            imageData: MOBIFixture.tinyPNG,
            coverOffset: 0,
            extraRecordsBefore: 5
        )
        let url = try MOBIFixture.writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = MOBICoverExtractor.extractCover(from: url)
        #expect(image != nil, "firstImageRecord should account for extra records")
    }
}

// MARK: - AZW3MetadataExtractor Integration

@Suite("AZW3MetadataExtractor - Cover Extraction")
struct AZW3MetadataExtractorCoverTests {

    @Test("extractCoverImage delegates to MOBICoverExtractor")
    func extractCoverImageDelegates() async throws {
        let data = MOBIFixture.buildMOBI(
            imageData: MOBIFixture.tinyPNG,
            coverOffset: 0
        )
        let url = try MOBIFixture.writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = AZW3MetadataExtractor()
        let image = await extractor.extractCoverImage(from: url)
        #expect(image != nil, "AZW3MetadataExtractor should delegate to MOBICoverExtractor")
    }

    @Test("extractCoverImage returns nil for invalid file")
    func extractCoverImageInvalid() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).azw3")
        let extractor = AZW3MetadataExtractor()
        let image = await extractor.extractCoverImage(from: url)
        #expect(image == nil)
    }
}
