// Purpose: Dedicated rebuildable store for semantic chunk metadata and book index headers.
// Kept separate from FTS SQLite tables and user-authored annotation data.

import Foundation

actor SemanticIndexMetadataStore {
    private let storageDirectory: URL
    private let fileManager = FileManager.default
    private var inMemoryIndex: [String: SemanticIndexMetadata] = [:]
    private var vectorKeyToChunk: [UInt64: SemanticChunkMetadata] = [:]

    init(storageDirectory: URL? = nil) {
        if let explicit = storageDirectory {
            self.storageDirectory = explicit
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.storageDirectory = appSupport.appendingPathComponent("vreader/SemanticIndex/metadata", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
    }

    func save(metadata: SemanticIndexMetadata, chunks: [SemanticChunkMetadata]) throws {
        inMemoryIndex[metadata.bookFingerprintKey] = metadata
        for chunk in chunks {
            vectorKeyToChunk[chunk.vectorKey] = chunk
        }

        let bookDir = storageDirectory.appendingPathComponent(metadata.bookFingerprintKey, isDirectory: true)
        try fileManager.createDirectory(at: bookDir, withIntermediateDirectories: true)

        let metaURL = bookDir.appendingPathComponent("index_meta.json")
        let chunksURL = bookDir.appendingPathComponent("chunks.json")

        let metaData = try JSONEncoder().encode(metadata)
        try metaData.write(to: metaURL, options: .atomic)

        let chunksData = try JSONEncoder().encode(chunks)
        try chunksData.write(to: chunksURL, options: .atomic)
    }

    func fetchMetadata(forBook fingerprintKey: String) -> SemanticIndexMetadata? {
        if let cached = inMemoryIndex[fingerprintKey] { return cached }
        let metaURL = storageDirectory.appendingPathComponent(fingerprintKey).appendingPathComponent("index_meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(SemanticIndexMetadata.self, from: data) else {
            return nil
        }
        inMemoryIndex[fingerprintKey] = meta
        return meta
    }

    func fetchChunk(byVectorKey vectorKey: UInt64) -> SemanticChunkMetadata? {
        vectorKeyToChunk[vectorKey]
    }

    func fetchChunks(byVectorKeys vectorKeys: [UInt64]) -> [SemanticChunkMetadata] {
        vectorKeys.compactMap { vectorKeyToChunk[$0] }
    }

    func remove(forBook fingerprintKey: String) throws {
        inMemoryIndex.removeValue(forKey: fingerprintKey)
        vectorKeyToChunk = vectorKeyToChunk.filter { $0.value.bookFingerprintKey != fingerprintKey }

        let bookDir = storageDirectory.appendingPathComponent(fingerprintKey, isDirectory: true)
        if fileManager.fileExists(atPath: bookDir.path) {
            try fileManager.removeItem(at: bookDir)
        }
    }

    func removeAll() throws {
        inMemoryIndex.removeAll()
        vectorKeyToChunk.removeAll()
        if fileManager.fileExists(atPath: storageDirectory.path) {
            try fileManager.removeItem(at: storageDirectory)
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        }
    }
}
