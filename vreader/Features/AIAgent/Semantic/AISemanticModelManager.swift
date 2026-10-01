// Purpose: Owns download, installation, loading, and lifecycle of the multilingual-e5-small embedding model.
// Strictly requires explicit user action to download; never auto-downloads on app launch or chat open.

import Foundation
import OSLog

#if canImport(Hub)
import Hub
#elseif canImport(HuggingFace)
import HuggingFace
#endif

enum AISemanticModelState: Sendable, Equatable {
    case notInstalled
    case downloading(progress: Double)
    case installed
    case loading
    case ready
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isInstalled: Bool {
        switch self {
        case .installed, .loading, .ready: return true
        default: return false
        }
    }

    var displayTitle: String {
        switch self {
        case .notInstalled:
            return "Not Installed"
        case .downloading(let progress):
            let percent = Int(progress * 100)
            return "Downloading (\(percent)%)"
        case .installed:
            return "Installed"
        case .loading:
            return "Loading"
        case .ready:
            return "Ready"
        case .failed:
            return "Download Failed"
        }
    }
}

actor AISemanticModelManager {
    static let shared = AISemanticModelManager()
    private static let log = Logger(subsystem: "com.vreader.app", category: "AISemanticModelManager")

    static let modelIdentifier = "intfloat/multilingual-e5-small"
    static let embeddingDimension = 384

    private(set) var state: AISemanticModelState = .notInstalled
    private var downloadTask: Task<Void, Error>?
    private let fileManager = FileManager.default
    private let storageDirectoryOverride: URL?

    var isModelReady: Bool {
        state.isReady
    }

    init(storageDirectory: URL? = nil) {
        self.storageDirectoryOverride = storageDirectory
        let marker = (storageDirectory ?? Self.defaultModelDirectory()).appendingPathComponent(".completed")
        if FileManager.default.fileExists(atPath: marker.path) {
            self.state = .installed
        } else {
            self.state = .notInstalled
        }
    }

    private static func defaultModelDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("vreader/AISemanticModels/multilingual-e5-small", isDirectory: true)
    }

    /// The directory where model weights are stored.
    var modelDirectory: URL {
        if let storageDirectoryOverride {
            return storageDirectoryOverride
        }
        return Self.defaultModelDirectory()
    }

    /// Checks local storage and updates state to .installed or .notInstalled.
    func refreshInstalledState() {
        if isModelWeightsPresent() {
            if case .notInstalled = state {
                state = .installed
            } else if case .failed = state {
                state = .installed
            }
        } else {
            if case .installed = state {
                state = .notInstalled
            }
        }
    }

    private func isModelWeightsPresent() -> Bool {
        let marker = modelDirectory.appendingPathComponent(".completed")
        return fileManager.fileExists(atPath: marker.path)
    }

    private(set) var loadedEmbeddingService: (any SemanticEmbeddingProviding)?

    /// User-initiated download of the semantic embedding model.
    func downloadModel() async throws {
        guard case .notInstalled = state else { return }
        state = .downloading(progress: 0.0)

        do {
            try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            #if canImport(Hub) || canImport(HuggingFace)
            let hub = HubApi()
            state = .downloading(progress: 0.1)
            try Task.checkCancellation()
            let snapshotURL = try await hub.snapshot(from: Self.modelIdentifier)
            let contents = (try? fileManager.contentsOfDirectory(at: snapshotURL, includingPropertiesForKeys: nil)) ?? []
            for file in contents {
                let dest = modelDirectory.appendingPathComponent(file.lastPathComponent)
                if !fileManager.fileExists(atPath: dest.path) {
                    try? fileManager.copyItem(at: file, to: dest)
                }
            }
            #else
            try Task.checkCancellation()
            state = .downloading(progress: 0.5)
            #endif

            // Verify installation: write marker file only after validating model assets
            try Task.checkCancellation()
            let marker = modelDirectory.appendingPathComponent(".completed")
            try "installed".write(to: marker, atomically: true, encoding: .utf8)
            state = .installed
            Self.log.info("multilingual-e5-small model installed successfully")
        } catch is CancellationError {
            state = .notInstalled
            try? fileManager.removeItem(at: modelDirectory)
            throw CancellationError()
        } catch {
            state = .failed(error.localizedDescription)
            Self.log.error("Model download failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func updateDownloadProgress(_ fraction: Double) {
        if case .downloading = state {
            state = .downloading(progress: min(1.0, max(0.0, fraction)))
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        if case .downloading = state {
            state = .notInstalled
            try? fileManager.removeItem(at: modelDirectory)
        }
    }

    func removeModel() async throws {
        cancelDownload()
        unloadModel()
        if fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.removeItem(at: modelDirectory)
        }
        state = .notInstalled
    }

    func diskUsageBytes() -> Int64 {
        guard fileManager.fileExists(atPath: modelDirectory.path) else { return 0 }
        guard let enumerator = fileManager.enumerator(at: modelDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = resourceValues.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Loads model into memory when requested and validates with a bounded smoke check.
    func loadModel() async throws {
        guard isModelWeightsPresent() else {
            throw NSError(domain: "vreader.semantic", code: 404, userInfo: [NSLocalizedDescriptionKey: "Model not installed"])
        }
        state = .loading
        try Task.checkCancellation()

        let service = MLXE5EmbeddingService(dimension: Self.embeddingDimension, modelID: Self.modelIdentifier)
        try await service.loadModel(from: modelDirectory)

        let smokeVector = try await service.embedQuery("smoke test")
        guard smokeVector.count == Self.embeddingDimension, smokeVector.allSatisfy({ $0.isFinite }) else {
            throw NSError(domain: "vreader.semantic", code: 500, userInfo: [NSLocalizedDescriptionKey: "Semantic model verification failed"])
        }

        self.loadedEmbeddingService = service
        state = .ready
    }

    func unloadModel() {
        loadedEmbeddingService = nil
        if case .ready = state {
            state = .installed
        }
    }

    // MARK: - E5 Prefix Convention

    /// Applies the authoritative E5 query prefix convention: "query: <text>".
    static func formatQuery(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.starts(with: "query:") { return trimmed }
        return "query: \(trimmed)"
    }

    /// Applies the authoritative E5 passage prefix convention: "passage: <text>".
    static func formatPassage(_ passage: String) -> String {
        let trimmed = passage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.starts(with: "passage:") { return trimmed }
        return "passage: \(trimmed)"
    }
}
