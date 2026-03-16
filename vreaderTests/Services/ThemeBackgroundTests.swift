import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader
@Suite("ThemeBackgroundStore") struct ThemeBackgroundTests {
    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("TBT-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true); return tmp
    }
    #if canImport(UIKit)
    private func makeTestImage(width: Int = 100, height: Int = 100) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    @Test func saveBackground_savesImageToDisk() throws {
        let d = try makeTempDir(); try ThemeBackgroundStore.saveBackground(makeTestImage(), for: "light", baseDirectory: d)
        #expect(FileManager.default.fileExists(atPath: ThemeBackgroundStore.backgroundPath(for: "light", baseDirectory: d).path))
        try? FileManager.default.removeItem(at: d)
    }
    @Test func saveBackground_resizesLargeImage() throws {
        let d = try makeTempDir(); try ThemeBackgroundStore.saveBackground(makeTestImage(width: 2048, height: 3072), for: "light", baseDirectory: d)
        let p = ThemeBackgroundStore.backgroundPath(for: "light", baseDirectory: d)
        if let data = try? Data(contentsOf: p), let img = UIImage(data: data) { #expect(max(img.size.width, img.size.height) <= 1024) }
        try? FileManager.default.removeItem(at: d)
    }
    @Test func saveBackground_doesNotResizeSmallImage() throws {
        let d = try makeTempDir(); try ThemeBackgroundStore.saveBackground(makeTestImage(width: 512, height: 512), for: "dark", baseDirectory: d)
        let p = ThemeBackgroundStore.backgroundPath(for: "dark", baseDirectory: d)
        if let data = try? Data(contentsOf: p), let img = UIImage(data: data) { #expect(img.size.width <= 1024); #expect(img.size.height <= 1024) }
        try? FileManager.default.removeItem(at: d)
    }
    @Test func loadBackground_returnsNil_whenNone() throws {
        let d = try makeTempDir(); #expect(ThemeBackgroundStore.loadBackground(for: "light", baseDirectory: d) == nil)
        try? FileManager.default.removeItem(at: d)
    }
    @Test func loadBackground_returnsImage_whenSet() throws {
        let d = try makeTempDir(); try ThemeBackgroundStore.saveBackground(makeTestImage(), for: "light", baseDirectory: d)
        #expect(ThemeBackgroundStore.loadBackground(for: "light", baseDirectory: d) != nil)
        try? FileManager.default.removeItem(at: d)
    }
    @Test func removeBackground_deletesFile() throws {
        let d = try makeTempDir(); try ThemeBackgroundStore.saveBackground(makeTestImage(), for: "s", baseDirectory: d)
        try ThemeBackgroundStore.removeBackground(for: "s", baseDirectory: d)
        #expect(!FileManager.default.fileExists(atPath: ThemeBackgroundStore.backgroundPath(for: "s", baseDirectory: d).path))
        try? FileManager.default.removeItem(at: d)
    }
    @Test func removeBackground_doesNotThrow_whenNoFile() throws {
        let d = try makeTempDir(); try ThemeBackgroundStore.removeBackground(for: "x", baseDirectory: d)
        try? FileManager.default.removeItem(at: d)
    }
    @Test func saveBackground_overwritesExisting() throws {
        let d = try makeTempDir()
        try ThemeBackgroundStore.saveBackground(makeTestImage(width: 100, height: 100), for: "light", baseDirectory: d)
        try ThemeBackgroundStore.saveBackground(makeTestImage(width: 200, height: 200), for: "light", baseDirectory: d)
        let loaded = ThemeBackgroundStore.loadBackground(for: "light", baseDirectory: d)
        #expect(loaded != nil); #expect(loaded!.size.width == 200)
        try? FileManager.default.removeItem(at: d)
    }
    #endif
    @Test func backgroundPath_uniquePerTheme() throws {
        let d = try makeTempDir()
        #expect(ThemeBackgroundStore.backgroundPath(for: "light", baseDirectory: d) != ThemeBackgroundStore.backgroundPath(for: "dark", baseDirectory: d))
        try? FileManager.default.removeItem(at: d)
    }
    @Test func backgroundPath_usesJPEGExtension() throws {
        let d = try makeTempDir()
        #expect(ThemeBackgroundStore.backgroundPath(for: "light", baseDirectory: d).pathExtension == "jpg")
        try? FileManager.default.removeItem(at: d)
    }
}
