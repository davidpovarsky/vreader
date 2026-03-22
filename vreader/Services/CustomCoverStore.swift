// Purpose: Manages saving, loading, and deleting custom cover images for books.
// Covers are stored as JPEG files in <baseDirectory>/CustomCovers/<sanitizedKey>.jpg.
//
// Key decisions:
// - JPEG compression at quality 0.8 to balance size and quality.
// - Images are resized to max 512x512 before saving (no upscaling).
// - Fingerprint keys are sanitized (colons, slashes replaced) for filesystem safety.
// - All methods accept an optional baseDirectory for testability (defaults to App Support).
// - Enum with static methods — no instance state needed.
//
// @coordinates-with: LibraryView.swift, BookCardView.swift, BookRowView.swift, LibraryBookItem.swift

import UIKit

enum CustomCoverStore {

    // MARK: - Constants

    private static let subdirectory = "CustomCovers"
    private static let jpegQuality: CGFloat = 0.8
    private static let maxDimension: CGFloat = 512

    // MARK: - Public API

    /// Returns the file URL where a custom cover would be stored for the given key.
    static func coverPath(
        for fingerprintKey: String,
        baseDirectory: URL? = nil
    ) -> URL {
        let base = baseDirectory ?? defaultBaseDirectory
        let dir = base.appendingPathComponent(subdirectory, isDirectory: true)
        let safeName = sanitize(fingerprintKey)
        return dir.appendingPathComponent(safeName).appendingPathExtension("jpg")
    }

    /// Saves a cover image for the given book, resizing if necessary.
    /// Replaces any existing custom cover.
    static func saveCover(
        _ image: UIImage,
        for fingerprintKey: String,
        baseDirectory: URL? = nil
    ) throws {
        let path = coverPath(for: fingerprintKey, baseDirectory: baseDirectory)
        let dir = path.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let resized = resizeIfNeeded(image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: jpegQuality) else {
            throw CustomCoverError.encodingFailed
        }

        try data.write(to: path, options: .atomic)
    }

    /// Loads the custom cover image for the given book, or nil if none exists.
    static func loadCover(
        for fingerprintKey: String,
        baseDirectory: URL? = nil
    ) -> UIImage? {
        let path = coverPath(for: fingerprintKey, baseDirectory: baseDirectory)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return UIImage(contentsOfFile: path.path)
    }

    /// Removes the custom cover for the given book. No-op if none exists.
    static func removeCover(
        for fingerprintKey: String,
        baseDirectory: URL? = nil
    ) throws {
        let path = coverPath(for: fingerprintKey, baseDirectory: baseDirectory)
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        try FileManager.default.removeItem(at: path)
    }

    /// Returns true if a custom cover exists for the given book.
    static func hasCover(
        for fingerprintKey: String,
        baseDirectory: URL? = nil
    ) -> Bool {
        let path = coverPath(for: fingerprintKey, baseDirectory: baseDirectory)
        return FileManager.default.fileExists(atPath: path.path)
    }

    // MARK: - Private

    private static var defaultBaseDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Sanitizes a fingerprint key for use as a filename.
    /// Replaces colons, slashes, and other unsafe characters with underscores.
    private static func sanitize(_ key: String) -> String {
        let unsafe = CharacterSet.alphanumerics.inverted
        return key.unicodeScalars
            .map { unsafe.contains($0) ? "_" : String($0) }
            .joined()
    }

    /// Resizes the image so that neither pixel dimension exceeds maxDimension.
    /// Does not upscale — returns the original if it is already small enough.
    /// Uses scale 1.0 so JPEG output dimensions match exactly.
    private static func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        // Use pixel dimensions to avoid scale mismatch when saving as JPEG.
        let pixelWidth = CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale))
        let pixelHeight = CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
        guard pixelWidth > maxDimension || pixelHeight > maxDimension else {
            return image
        }

        let ratio = min(maxDimension / pixelWidth, maxDimension / pixelHeight)
        let newSize = CGSize(
            width: (pixelWidth * ratio).rounded(.down),
            height: (pixelHeight * ratio).rounded(.down)
        )

        // Render at scale 1.0 so the output image's point size equals its pixel size.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Errors

enum CustomCoverError: Error, LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode image as JPEG."
        }
    }
}
