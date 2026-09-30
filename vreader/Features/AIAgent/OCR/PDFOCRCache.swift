// Purpose: Rebuildable on-disk cache for PDF OCR results.
// Keyed by book fingerprint + page index + pipeline version.

import Foundation

actor PDFOCRCache {
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let pipelineVersion: String
    private var inMemoryCache: [String: PDFOCRResult] = [:]

    init(
        pipelineVersion: String = PDFOCRPolicy.currentPipelineVersion,
        cacheDirectory: URL? = nil
    ) {
        self.pipelineVersion = pipelineVersion
        if let explicit = cacheDirectory {
            self.cacheDirectory = explicit
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheDirectory = appSupport.appendingPathComponent("vreader/OCRCache", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    private func cacheKey(bookKey: String, pageIndex: Int) -> String {
        "\(bookKey)_\(pageIndex)_\(pipelineVersion)"
    }

    func get(bookKey: String, pageIndex: Int) -> PDFOCRResult? {
        let key = cacheKey(bookKey: bookKey, pageIndex: pageIndex)
        if let cached = inMemoryCache[key] { return cached }

        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: fileURL),
              let result = try? JSONDecoder().decode(PDFOCRResult.self, from: data) else {
            return nil
        }
        inMemoryCache[key] = result
        return result
    }

    func set(_ result: PDFOCRResult) throws {
        let key = cacheKey(bookKey: result.bookFingerprintKey, pageIndex: result.pageIndex)
        inMemoryCache[key] = result

        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        let data = try JSONEncoder().encode(result)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear(forBook bookKey: String) throws {
        inMemoryCache = inMemoryCache.filter { !$0.key.starts(with: "\(bookKey)_") }
        guard let files = try? fileManager.contentsOfDirectory(atPath: cacheDirectory.path) else { return }
        for file in files where file.starts(with: "\(bookKey)_") {
            try fileManager.removeItem(at: cacheDirectory.appendingPathComponent(file))
        }
    }

    func clearAll() throws {
        inMemoryCache.removeAll()
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
}
