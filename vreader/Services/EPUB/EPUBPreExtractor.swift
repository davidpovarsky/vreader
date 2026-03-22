// Purpose: Pre-extracts EPUB contents to persistent cache at import time.
// When the user later opens the EPUB, EPUBParser can find the cache and
// skip the expensive on-demand extraction.
//
// Key decisions:
// - Cache key uses filename + file size + modification date (integer seconds).
// - Cache is stored under Caches/EPUBCache/<cacheKey>/.
// - Existence check uses META-INF/container.xml as the sentinel file.
// - Fire-and-forget: all errors are silently caught (on-demand fallback handles them).
// - No actor isolation needed — stateless utility with async static method.
//
// @coordinates-with: EPUBParser.swift, ZIPReader.swift, BookImporter.swift

import Foundation

/// Pre-extracts EPUB contents to persistent cache at import time.
/// When the user later opens the EPUB, EPUBParser finds the cache and skips extraction.
enum EPUBPreExtractor {

    /// Pre-extracts all EPUB entries to the persistent cache directory.
    /// Fire-and-forget — errors are silently ignored (on-demand fallback handles them).
    static func preExtract(epubURL: URL) async {
        do {
            let zip = try ZIPReader(fileURL: epubURL)

            let cacheDir = try cacheDirectory(for: epubURL)

            // Skip if already cached (sentinel: META-INF/container.xml)
            let containerPath = cacheDir
                .appendingPathComponent("META-INF")
                .appendingPathComponent("container.xml")
            if FileManager.default.fileExists(atPath: containerPath.path) { return }

            // Extract everything
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try await zip.extractAll(to: cacheDir)
        } catch {
            // Silently ignore — on-demand extraction handles any failures
        }
    }

    // MARK: - Cache Key

    /// Computes the persistent cache directory for a given EPUB file.
    /// Cache key: "{filename}-{fileSize}-{modDateInt}"
    static func cacheDirectory(for epubURL: URL) throws -> URL {
        let attrs = try FileManager.default.attributesOfItem(atPath: epubURL.path)
        let fileSize = (attrs[.size] as? Int64) ?? 0
        let modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(epubURL.lastPathComponent)-\(fileSize)-\(Int(modDate))"
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EPUBCache", isDirectory: true)
            .appendingPathComponent(cacheKey, isDirectory: true)
    }
}
