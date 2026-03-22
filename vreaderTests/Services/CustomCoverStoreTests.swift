// Purpose: Tests for CustomCoverStore — saving, loading, removing custom
// book cover images per fingerprint key.
//
// @coordinates-with: CustomCoverStore.swift, LibraryBookItem.swift

import Testing
import UIKit
@testable import vreader

@Suite("CustomCoverStore")
struct CustomCoverStoreTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CustomCoverStoreTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeTestImage(color: UIColor = .red) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }

    private func makeLargeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format)
        return renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
    }

    // MARK: - coverPath

    @Test func coverPath_uniquePerBook() {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let path1 = CustomCoverStore.coverPath(for: "epub:abc123:1024", baseDirectory: baseDir)
        let path2 = CustomCoverStore.coverPath(for: "epub:def456:2048", baseDirectory: baseDir)
        #expect(path1 != path2)
    }

    @Test func coverPath_sanitizesColons() {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let path = CustomCoverStore.coverPath(for: "epub:abc:123", baseDirectory: baseDir)
        #expect(!path.lastPathComponent.contains(":"))
        #expect(path.pathExtension == "jpg")
    }

    // MARK: - saveCover

    @Test func setCover_savesImageToDisk() throws {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let image = makeTestImage()
        let key = "epub:save_test:1024"
        try CustomCoverStore.saveCover(image, for: key, baseDirectory: baseDir)
        let path = CustomCoverStore.coverPath(for: key, baseDirectory: baseDir)
        #expect(FileManager.default.fileExists(atPath: path.path))
    }

    @Test func setCover_replacesExisting() throws {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let key = "epub:replace_test:1024"
        let image1 = makeTestImage(color: .red)
        let image2 = makeTestImage(color: .green)
        try CustomCoverStore.saveCover(image1, for: key, baseDirectory: baseDir)
        let data1 = try Data(contentsOf: CustomCoverStore.coverPath(for: key, baseDirectory: baseDir))
        try CustomCoverStore.saveCover(image2, for: key, baseDirectory: baseDir)
        let data2 = try Data(contentsOf: CustomCoverStore.coverPath(for: key, baseDirectory: baseDir))
        #expect(FileManager.default.fileExists(atPath: CustomCoverStore.coverPath(for: key, baseDirectory: baseDir).path))
        #expect(UIImage(data: data1) != nil)
        #expect(UIImage(data: data2) != nil)
    }

    @Test func setCover_resizesLargeImage() throws {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let key = "epub:resize_test:1024"
        let largeImage = makeLargeImage()
        #expect(largeImage.size.width == 1024)
        #expect(largeImage.size.height == 1024)
        try CustomCoverStore.saveCover(largeImage, for: key, baseDirectory: baseDir)
        let loadedImage = CustomCoverStore.loadCover(for: key, baseDirectory: baseDir)
        #expect(loadedImage != nil)
        #expect(loadedImage!.size.width <= 512)
        #expect(loadedImage!.size.height <= 512)
    }

    @Test func setCover_doesNotUpscaleSmallImage() throws {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let key = "epub:small_test:1024"
        let smallImage = makeTestImage()
        try CustomCoverStore.saveCover(smallImage, for: key, baseDirectory: baseDir)
        let loadedImage = CustomCoverStore.loadCover(for: key, baseDirectory: baseDir)
        #expect(loadedImage != nil)
        #expect(loadedImage!.size.width <= 10)
        #expect(loadedImage!.size.height <= 10)
    }

    // MARK: - loadCover

    @Test func getCover_returnsNil_whenNoCover() {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let result = CustomCoverStore.loadCover(for: "epub:no_cover:999", baseDirectory: baseDir)
        #expect(result == nil)
    }

    @Test func getCover_returnsImage_whenCoverSet() throws {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let key = "epub:load_test:1024"
        let image = makeTestImage()
        try CustomCoverStore.saveCover(image, for: key, baseDirectory: baseDir)
        let loaded = CustomCoverStore.loadCover(for: key, baseDirectory: baseDir)
        #expect(loaded != nil)
    }

    // MARK: - removeCover

    @Test func removeCover_deletesFile() throws {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let key = "epub:remove_test:1024"
        let image = makeTestImage()
        try CustomCoverStore.saveCover(image, for: key, baseDirectory: baseDir)
        #expect(CustomCoverStore.hasCover(for: key, baseDirectory: baseDir))
        try CustomCoverStore.removeCover(for: key, baseDirectory: baseDir)
        #expect(!CustomCoverStore.hasCover(for: key, baseDirectory: baseDir))
        let path = CustomCoverStore.coverPath(for: key, baseDirectory: baseDir)
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    @Test func removeCover_noOpWhenNoCover() throws {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        try CustomCoverStore.removeCover(for: "epub:nonexistent:999", baseDirectory: baseDir)
    }

    // MARK: - hasCover

    @Test func hasCover_falseWhenNoCover() {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        #expect(!CustomCoverStore.hasCover(for: "epub:no_cover:111", baseDirectory: baseDir))
    }

    @Test func hasCover_trueAfterSave() throws {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let key = "epub:has_test:1024"
        let image = makeTestImage()
        try CustomCoverStore.saveCover(image, for: key, baseDirectory: baseDir)
        #expect(CustomCoverStore.hasCover(for: key, baseDirectory: baseDir))
    }

    @Test func hasCover_falseAfterRemove() throws {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let key = "epub:has_remove_test:1024"
        let image = makeTestImage()
        try CustomCoverStore.saveCover(image, for: key, baseDirectory: baseDir)
        try CustomCoverStore.removeCover(for: key, baseDirectory: baseDir)
        #expect(!CustomCoverStore.hasCover(for: key, baseDirectory: baseDir))
    }

    // MARK: - Edge Cases

    @Test func emptyFingerprintKey_handledGracefully() throws {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let image = makeTestImage()
        try CustomCoverStore.saveCover(image, for: "", baseDirectory: baseDir)
        let loaded = CustomCoverStore.loadCover(for: "", baseDirectory: baseDir)
        #expect(loaded != nil)
    }

    @Test func fingerprintKey_withSlashes_sanitized() {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let path = CustomCoverStore.coverPath(for: "epub:abc/def:123", baseDirectory: baseDir)
        #expect(!path.lastPathComponent.contains("/"))
    }

    @Test func coverPath_isUnderCustomCoversSubdirectory() {
        let baseDir = makeTempDir()
        defer { cleanup(baseDir) }
        let path = CustomCoverStore.coverPath(for: "epub:abc:123", baseDirectory: baseDir)
        #expect(path.pathComponents.contains("CustomCovers"))
    }
}
