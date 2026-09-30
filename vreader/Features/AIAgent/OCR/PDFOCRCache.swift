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

    init(
        storageDirectory: URL?,
        currentPipelineVersion: Int = 1
    ) {
        self.init(pipelineVersion: "v\(currentPipelineVersion)", cacheDirectory: storageDirectory)
    }

    init(
        storageDirectory: URL?,
        pipelineVersion: String
    ) {
        self.init(pipelineVersion: pipelineVersion, cacheDirectory: storageDirectory)
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

    func get(bookFingerprintKey: String, pageIndex: Int) -> PDFOCRResult? {
        get(bookKey: bookFingerprintKey, pageIndex: pageIndex)
    }

    func set(_ result: PDFOCRResult, for bookKey: String? = nil, pageIndex: Int? = nil) {
        let targetKey = bookKey ?? result.bookFingerprintKey
        let targetIndex = pageIndex ?? result.pageIndex
        let key = cacheKey(bookKey: targetKey, pageIndex: targetIndex)
        inMemoryCache[key] = result

        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        guard let data = try? JSONEncoder().encode(result) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear(forBook bookKey: String) {
        inMemoryCache = inMemoryCache.filter { !$0.key.starts(with: "\(bookKey)_") }
        guard let files = try? fileManager.contentsOfDirectory(atPath: cacheDirectory.path) else { return }
        for file in files where file.starts(with: "\(bookKey)_") {
            try? fileManager.removeItem(at: cacheDirectory.appendingPathComponent(file))
        }
    }

    func clear(for bookKey: String) {
        clear(forBook: bookKey)
    }

    func clearAll() {
        inMemoryCache.removeAll()
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.removeItem(at: cacheDirectory)
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
}
