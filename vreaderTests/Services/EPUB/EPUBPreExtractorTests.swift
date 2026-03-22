// Purpose: Tests for EPUBPreExtractor — pre-extracts EPUB to persistent cache at import time.

import Testing
import Foundation
@testable import vreader

// MARK: - Test ZIP Builder (same pattern as EPUBParserTests)

private struct TestZIPBuilder {
    struct Entry {
        let path: String
        let content: Data
    }

    static func createZIP(entries: [Entry]) throws -> URL {
        var archive = Data()
        var localHeaderOffsets: [Int] = []

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            localHeaderOffsets.append(archive.count)
            archive.append(buildLocalFileHeader(nameData: nameData, content: entry.content))
            archive.append(nameData)
            archive.append(entry.content)
        }

        let cdOffset = archive.count
        for (i, entry) in entries.enumerated() {
            let nameData = Data(entry.path.utf8)
            archive.append(buildCentralDirectoryEntry(
                nameData: nameData,
                content: entry.content,
                localHeaderOffset: UInt32(localHeaderOffsets[i])
            ))
            archive.append(nameData)
        }
        let cdSize = archive.count - cdOffset

        archive.append(buildEOCD(
            entryCount: UInt16(entries.count),
            cdSize: UInt32(cdSize),
            cdOffset: UInt32(cdOffset)
        ))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("preextract-test-\(UUID().uuidString).epub")
        try archive.write(to: url)
        return url
    }

    private static func buildLocalFileHeader(nameData: Data, content: Data) -> Data {
        var h = Data()
        h.appendUInt32LE(0x04034b50)
        h.appendUInt16LE(20)
        h.appendUInt16LE(0)
        h.appendUInt16LE(0)  // stored
        h.appendUInt16LE(0)
        h.appendUInt16LE(0)
        h.appendUInt32LE(0)  // crc32
        h.appendUInt32LE(UInt32(content.count))
        h.appendUInt32LE(UInt32(content.count))
        h.appendUInt16LE(UInt16(nameData.count))
        h.appendUInt16LE(0)
        return h
    }

    private static func buildCentralDirectoryEntry(
        nameData: Data,
        content: Data,
        localHeaderOffset: UInt32
    ) -> Data {
        var e = Data()
        e.appendUInt32LE(0x02014b50)
        e.appendUInt16LE(20)
        e.appendUInt16LE(20)
        e.appendUInt16LE(0)
        e.appendUInt16LE(0)  // stored
        e.appendUInt16LE(0)
        e.appendUInt16LE(0)
        e.appendUInt32LE(0)  // crc32
        e.appendUInt32LE(UInt32(content.count))
        e.appendUInt32LE(UInt32(content.count))
        e.appendUInt16LE(UInt16(nameData.count))
        e.appendUInt16LE(0)
        e.appendUInt16LE(0)
        e.appendUInt16LE(0)
        e.appendUInt16LE(0)
        e.appendUInt32LE(0)
        e.appendUInt32LE(localHeaderOffset)
        return e
    }

    private static func buildEOCD(entryCount: UInt16, cdSize: UInt32, cdOffset: UInt32) -> Data {
        var e = Data()
        e.appendUInt32LE(0x06054b50)
        e.appendUInt16LE(0)
        e.appendUInt16LE(0)
        e.appendUInt16LE(entryCount)
        e.appendUInt16LE(entryCount)
        e.appendUInt32LE(cdSize)
        e.appendUInt32LE(cdOffset)
        e.appendUInt16LE(0)
        return e
    }
}

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

// MARK: - Minimal EPUB Template

private enum TestEPUBTemplate {
    static func containerXML(opfPath: String = "content.opf") -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="\(opfPath)" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.utf8)
    }

    static func contentOPF(title: String = "Test") -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>\(title)</dc:title>
          </metadata>
          <manifest>
            <item id="ch1" href="chapter.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="ch1"/></spine>
        </package>
        """.utf8)
    }

    static func minimalXHTML() -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head><title>Ch</title></head>
          <body><p>Hello</p></body>
        </html>
        """.utf8)
    }
}

// MARK: - Helper: build a minimal valid EPUB ZIP

private func makeMinimalEPUB() throws -> URL {
    try TestZIPBuilder.createZIP(entries: [
        .init(path: "META-INF/container.xml", content: TestEPUBTemplate.containerXML()),
        .init(path: "content.opf", content: TestEPUBTemplate.contentOPF()),
        .init(path: "chapter.xhtml", content: TestEPUBTemplate.minimalXHTML()),
    ])
}

/// Computes the same cache directory URL that EPUBPreExtractor uses,
/// so tests can verify the exact location.
private func expectedCacheDir(for epubURL: URL) throws -> URL {
    let attrs = try FileManager.default.attributesOfItem(atPath: epubURL.path)
    let fileSize = (attrs[.size] as? Int64) ?? 0
    let modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let cacheKey = "\(epubURL.lastPathComponent)-\(fileSize)-\(Int(modDate))"
    return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("EPUBCache", isDirectory: true)
        .appendingPathComponent(cacheKey, isDirectory: true)
}

// MARK: - Tests

@Suite("EPUBPreExtractor")
struct EPUBPreExtractorTests {

    // MARK: - Cleanup helper

    private func cleanupCacheDir(for epubURL: URL) {
        guard let cacheDir = try? expectedCacheDir(for: epubURL) else { return }
        try? FileManager.default.removeItem(at: cacheDir)
    }

    // MARK: - preExtract creates cache

    @Test("preExtract creates cache directory with container.xml")
    func preExtractCreatesCache() async throws {
        let epubURL = try makeMinimalEPUB()
        defer { try? FileManager.default.removeItem(at: epubURL) }
        defer { cleanupCacheDir(for: epubURL) }

        await EPUBPreExtractor.preExtract(epubURL: epubURL)

        let cacheDir = try expectedCacheDir(for: epubURL)
        let containerPath = cacheDir
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")
        #expect(FileManager.default.fileExists(atPath: containerPath.path),
                "container.xml should exist in cache after pre-extraction")

        // Verify OPF and chapter files also extracted
        let opfPath = cacheDir.appendingPathComponent("content.opf")
        #expect(FileManager.default.fileExists(atPath: opfPath.path),
                "content.opf should exist in cache")

        let chapterPath = cacheDir.appendingPathComponent("chapter.xhtml")
        #expect(FileManager.default.fileExists(atPath: chapterPath.path),
                "chapter.xhtml should exist in cache")
    }

    // MARK: - preExtract is idempotent (skips if cached)

    @Test("preExtract skips if cache already exists")
    func preExtractSkipsIfCached() async throws {
        let epubURL = try makeMinimalEPUB()
        defer { try? FileManager.default.removeItem(at: epubURL) }
        defer { cleanupCacheDir(for: epubURL) }

        // First extraction
        await EPUBPreExtractor.preExtract(epubURL: epubURL)

        let cacheDir = try expectedCacheDir(for: epubURL)
        let containerPath = cacheDir
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")

        // Record modification date of container.xml
        let attrs1 = try FileManager.default.attributesOfItem(atPath: containerPath.path)
        let modDate1 = attrs1[.modificationDate] as? Date

        // Brief pause to ensure filesystem timestamp would differ
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Second extraction — should be a no-op
        await EPUBPreExtractor.preExtract(epubURL: epubURL)

        let attrs2 = try FileManager.default.attributesOfItem(atPath: containerPath.path)
        let modDate2 = attrs2[.modificationDate] as? Date

        #expect(modDate1 == modDate2,
                "container.xml should not be re-extracted when cache exists")
    }

    // MARK: - Corrupt ZIP is silently ignored

    @Test("preExtract does not throw for corrupt/invalid ZIP file")
    func preExtractSilentOnCorruptZIP() async throws {
        let corruptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).epub")
        try Data("this is not a zip file".utf8).write(to: corruptURL)
        defer { try? FileManager.default.removeItem(at: corruptURL) }

        // Should complete without throwing
        await EPUBPreExtractor.preExtract(epubURL: corruptURL)

        // No crash, no exception — fire-and-forget semantics
    }

    // MARK: - Non-existent file is silently ignored

    @Test("preExtract does not throw for non-existent file")
    func preExtractSilentOnMissingFile() async {
        let missingURL = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).epub")

        // Should complete without throwing
        await EPUBPreExtractor.preExtract(epubURL: missingURL)
    }

    // MARK: - Cache key format matches expected pattern

    @Test("cache key format is filename-fileSize-modDateInt")
    func cacheKeyMatchesExpectedFormat() async throws {
        let epubURL = try makeMinimalEPUB()
        defer { try? FileManager.default.removeItem(at: epubURL) }
        defer { cleanupCacheDir(for: epubURL) }

        await EPUBPreExtractor.preExtract(epubURL: epubURL)

        let cacheDir = try expectedCacheDir(for: epubURL)

        // Verify the cache directory name follows the expected pattern
        let dirName = cacheDir.lastPathComponent
        let attrs = try FileManager.default.attributesOfItem(atPath: epubURL.path)
        let fileSize = (attrs[.size] as? Int64) ?? 0
        let modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        let expected = "\(epubURL.lastPathComponent)-\(fileSize)-\(Int(modDate))"
        #expect(dirName == expected,
                "Cache dir name '\(dirName)' should match expected pattern '\(expected)'")

        // Also verify the parent is EPUBCache
        let parentName = cacheDir.deletingLastPathComponent().lastPathComponent
        #expect(parentName == "EPUBCache")
    }

    // MARK: - cacheDirectory(for:) API matches test expectation

    @Test("cacheDirectory(for:) returns expected path structure")
    func cacheDirectoryAPIMatchesExpected() throws {
        let epubURL = try makeMinimalEPUB()
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let actual = try EPUBPreExtractor.cacheDirectory(for: epubURL)
        let expected = try expectedCacheDir(for: epubURL)

        #expect(actual == expected,
                "EPUBPreExtractor.cacheDirectory should match expected cache path")
    }

    // MARK: - Empty EPUB entries handled gracefully

    @Test("preExtract handles EPUB with empty files gracefully")
    func preExtractHandlesEmptyEntries() async throws {
        let epubURL = try TestZIPBuilder.createZIP(entries: [
            .init(path: "META-INF/container.xml", content: TestEPUBTemplate.containerXML()),
            .init(path: "content.opf", content: Data()), // empty OPF
        ])
        defer { try? FileManager.default.removeItem(at: epubURL) }
        defer { cleanupCacheDir(for: epubURL) }

        // Should complete without throwing — extracts whatever is in the ZIP
        await EPUBPreExtractor.preExtract(epubURL: epubURL)

        let cacheDir = try expectedCacheDir(for: epubURL)
        let containerPath = cacheDir
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")
        #expect(FileManager.default.fileExists(atPath: containerPath.path))
    }
}
