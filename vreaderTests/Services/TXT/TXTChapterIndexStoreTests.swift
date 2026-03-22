// Purpose: Tests for TXTChapterIndexStore — verifies round-trip persistence,
// cache invalidation on stale metadata, corrupt data handling, and atomic writes.
//
// @coordinates-with: TXTChapterIndexStore.swift, TXTChapterTypes.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private func makeSampleIndex(chapterCount: Int = 3) -> TXTChapterIndex {
    var chapters: [TXTChapter] = []
    for i in 0..<chapterCount {
        let ch = TXTChapter(
            index: i,
            title: "Chapter \(i + 1)",
            startByte: Int64(i * 1000),
            endByte: Int64((i + 1) * 1000),
            globalStartUTF16: i * 500,
            textLengthUTF16: 500
        )
        chapters.append(ch)
    }
    return TXTChapterIndex(
        chapters: chapters,
        totalBytes: Int64(chapterCount * 1000),
        detectedEncoding: "UTF-8",
        totalTextLengthUTF16: chapterCount * 500
    )
}

private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("TXTChapterIndexStoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private let sampleByteCount: Int64 = 3000
private let sampleModDate = Date(timeIntervalSince1970: 1700000000)

// MARK: - Tests

@Suite("TXTChapterIndexStore")
struct TXTChapterIndexStoreTests {

    @Test("save and load round-trips identical index")
    func testSaveAndLoad() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let index = makeSampleIndex()
        try TXTChapterIndexStore.save(index, cacheDir: dir, fileByteCount: sampleByteCount, fileModDate: sampleModDate)

        let loaded = TXTChapterIndexStore.load(cacheDir: dir, fileByteCount: sampleByteCount, fileModDate: sampleModDate)
        #expect(loaded != nil)
        #expect(loaded == index)
    }

    @Test("stale byte count returns nil")
    func testStaleByteCount() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let index = makeSampleIndex()
        try TXTChapterIndexStore.save(index, cacheDir: dir, fileByteCount: sampleByteCount, fileModDate: sampleModDate)

        let loaded = TXTChapterIndexStore.load(cacheDir: dir, fileByteCount: 9999, fileModDate: sampleModDate)
        #expect(loaded == nil)
    }

    @Test("stale mod date returns nil")
    func testStaleModDate() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let index = makeSampleIndex()
        try TXTChapterIndexStore.save(index, cacheDir: dir, fileByteCount: sampleByteCount, fileModDate: sampleModDate)

        let differentDate = Date(timeIntervalSince1970: 1700000001)
        let loaded = TXTChapterIndexStore.load(cacheDir: dir, fileByteCount: sampleByteCount, fileModDate: differentDate)
        #expect(loaded == nil)
    }

    @Test("missing file returns nil without crash")
    func testMissingFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let loaded = TXTChapterIndexStore.load(cacheDir: dir, fileByteCount: sampleByteCount, fileModDate: sampleModDate)
        #expect(loaded == nil)
    }

    @Test("corrupted JSON returns nil")
    func testCorruptedJSON() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let filePath = dir.appendingPathComponent("chapter-index.json")
        try Data("not valid json {{{".utf8).write(to: filePath)

        let loaded = TXTChapterIndexStore.load(cacheDir: dir, fileByteCount: sampleByteCount, fileModDate: sampleModDate)
        #expect(loaded == nil)
    }

    @Test("invalidate removes cached file")
    func testInvalidate() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let index = makeSampleIndex()
        try TXTChapterIndexStore.save(index, cacheDir: dir, fileByteCount: sampleByteCount, fileModDate: sampleModDate)

        TXTChapterIndexStore.invalidate(cacheDir: dir)

        let loaded = TXTChapterIndexStore.load(cacheDir: dir, fileByteCount: sampleByteCount, fileModDate: sampleModDate)
        #expect(loaded == nil)
    }

    @Test("file exists after atomic save")
    func testAtomicWrite() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let index = makeSampleIndex()
        try TXTChapterIndexStore.save(index, cacheDir: dir, fileByteCount: sampleByteCount, fileModDate: sampleModDate)

        let filePath = dir.appendingPathComponent("chapter-index.json")
        #expect(FileManager.default.fileExists(atPath: filePath.path))
    }

    @Test("empty index round-trips")
    func testEmptyIndex() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let emptyIndex = TXTChapterIndex(
            chapters: [],
            totalBytes: 0,
            detectedEncoding: "UTF-8",
            totalTextLengthUTF16: 0
        )
        try TXTChapterIndexStore.save(emptyIndex, cacheDir: dir, fileByteCount: 0, fileModDate: sampleModDate)

        let loaded = TXTChapterIndexStore.load(cacheDir: dir, fileByteCount: 0, fileModDate: sampleModDate)
        #expect(loaded != nil)
        #expect(loaded?.chapters.isEmpty == true)
        #expect(loaded?.totalTextLengthUTF16 == 0)
    }
}
