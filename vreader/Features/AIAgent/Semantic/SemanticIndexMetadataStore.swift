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

    func saveChunkMetadata(_ chunks: [SemanticChunkMetadata], for bookKey: String) throws {
        let meta = SemanticIndexMetadata(bookFingerprintKey: bookKey, chunkCount: chunks.count)
        try save(metadata: meta, chunks: chunks)
    }

    func metadata(for chunkID: String) -> SemanticChunkMetadata? {
        if let found = vectorKeyToChunk.values.first(where: { $0.chunkID == chunkID }) {
            return found
        }
        if let bookDirs = try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) {
            for dir in bookDirs {
                let chunksURL = dir.appendingPathComponent("chunks.json")
                if let data = try? Data(contentsOf: chunksURL),
                   let diskChunks = try? JSONDecoder().decode([SemanticChunkMetadata].self, from: data) {
                    for chunk in diskChunks {
                        vectorKeyToChunk[chunk.vectorKey] = chunk
                    }
                    if let found = diskChunks.first(where: { $0.chunkID == chunkID }) {
                        return found
                    }
                }
            }
        }
        return nil
    }

    func allChunks(for bookKey: String) -> [SemanticChunkMetadata] {
        let cached = vectorKeyToChunk.values.filter { $0.bookFingerprintKey == bookKey }
        if !cached.isEmpty {
            return Array(cached)
        }
        let chunksURL = storageDirectory.appendingPathComponent(bookKey).appendingPathComponent("chunks.json")
        guard let data = try? Data(contentsOf: chunksURL),
              let diskChunks = try? JSONDecoder().decode([SemanticChunkMetadata].self, from: data) else {
            return []
        }
        for chunk in diskChunks {
            vectorKeyToChunk[chunk.vectorKey] = chunk
        }
        return diskChunks
    }

    func deleteMetadata(for bookKey: String) throws {
        try remove(forBook: bookKey)
    }

    func fetchChunk(byVectorKey vectorKey: UInt64) -> SemanticChunkMetadata? {
        if let found = vectorKeyToChunk[vectorKey] {
            return found
        }
        if let bookDirs = try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) {
            for dir in bookDirs {
                let chunksURL = dir.appendingPathComponent("chunks.json")
                if let data = try? Data(contentsOf: chunksURL),
                   let diskChunks = try? JSONDecoder().decode([SemanticChunkMetadata].self, from: data) {
                    for chunk in diskChunks {
                        vectorKeyToChunk[chunk.vectorKey] = chunk
                    }
                    if let found = vectorKeyToChunk[vectorKey] {
                        return found
                    }
                }
            }
        }
        return nil
    }

    func fetchChunks(byVectorKeys vectorKeys: [UInt64]) -> [SemanticChunkMetadata] {
        vectorKeys.compactMap { fetchChunk(byVectorKey: $0) }
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
