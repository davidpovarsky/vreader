import Foundation
#if canImport(UIKit)
import UIKit
#endif
enum ThemeBackgroundStore {
    static let maxDimension: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.8
    static func backgroundPath(for themeName: String, baseDirectory: URL? = nil) -> URL {
        let base = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ThemeBackgrounds", isDirectory: true).appendingPathComponent(themeName).appendingPathExtension("jpg")
    }
    #if canImport(UIKit)
    static func saveBackground(_ image: UIImage, for themeName: String, baseDirectory: URL? = nil) throws {
        let path = backgroundPath(for: themeName, baseDirectory: baseDirectory)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let resized = resizeIfNeeded(image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: jpegQuality) else { throw ThemeBackgroundError.compressionFailed }
        try data.write(to: path, options: .atomic)
    }
    static func loadBackground(for themeName: String, baseDirectory: URL? = nil) -> UIImage? {
        let path = backgroundPath(for: themeName, baseDirectory: baseDirectory)
        guard FileManager.default.fileExists(atPath: path.path), let data = try? Data(contentsOf: path) else { return nil }
        return UIImage(data: data)
    }
    #endif
    static func removeBackground(for themeName: String, baseDirectory: URL? = nil) throws {
        let path = backgroundPath(for: themeName, baseDirectory: baseDirectory)
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        try FileManager.default.removeItem(at: path)
    }
    #if canImport(UIKit)
    private static func resizeIfNeeded(_ image: UIImage, maxDimension maxDim: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxDim || size.height > maxDim else { return image }
        let scale = size.width > size.height ? maxDim / size.width : maxDim / size.height
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    #endif
}
enum ThemeBackgroundError: Error { case compressionFailed }
