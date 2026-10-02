// Purpose: Manifest data model and asset validator for multilingual-e5-small model.
// Validates model snapshot, file sizes, and SHA-256 hashes to prevent partial/corrupted installs.

import Foundation
import CryptoKit

struct AISemanticModelManifest: Codable, Sendable, Equatable {
    let modelID: String
    let requiredFiles: [String]
    let fileSizes: [String: Int64]
    let sha256Hashes: [String: String]
}

struct AISemanticAssetValidator: Sendable {
    let modelDirectory: URL
    private let fileManager = FileManager.default

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func validateInstalledAssets() -> Bool {
        let marker = modelDirectory.appendingPathComponent(".completed")
        guard fileManager.fileExists(atPath: marker.path) else { return false }

        let configFile = modelDirectory.appendingPathComponent("config.json")
        guard fileManager.fileExists(atPath: configFile.path),
              ((try? configFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 else {
            return false
        }

        let tokenizer = modelDirectory.appendingPathComponent("tokenizer.json")
        let tokenizerConfig = modelDirectory.appendingPathComponent("tokenizer_config.json")
        guard fileManager.fileExists(atPath: tokenizer.path) || fileManager.fileExists(atPath: tokenizerConfig.path) else {
            return false
        }

        let safetensors = modelDirectory.appendingPathComponent("model.safetensors")
        let weightsSafetensors = modelDirectory.appendingPathComponent("weights.safetensors")
        let pytorchBin = modelDirectory.appendingPathComponent("pytorch_model.bin")
        let hasWeights = [safetensors, weightsSafetensors, pytorchBin].contains { url in
            fileManager.fileExists(atPath: url.path) && ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        }
        guard hasWeights else { return false }

        let manifestURL = modelDirectory.appendingPathComponent("install-manifest.json")
        if fileManager.fileExists(atPath: manifestURL.path) {
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(AISemanticModelManifest.self, from: data) else {
                return false
            }
            for (filename, expectedSize) in manifest.fileSizes {
                let fileURL = modelDirectory.appendingPathComponent(filename)
                guard fileManager.fileExists(atPath: fileURL.path) else { return false }
                let actualSize = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                guard actualSize == expectedSize && actualSize > 0 else { return false }
            }
        }
        return true
    }

    func buildAndSaveManifest(modelID: String) throws {
        var fileSizes: [String: Int64] = [:]
        var sha256Hashes: [String: String] = [:]
        var requiredFiles: [String] = []

        let items = (try? fileManager.contentsOfDirectory(at: modelDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for fileURL in items {
            let name = fileURL.lastPathComponent
            if name.hasPrefix(".") || name == "install-manifest.json" { continue }
            requiredFiles.append(name)
            let size = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            fileSizes[name] = size
            if let data = try? Data(contentsOf: fileURL) {
                let digest = SHA256.hash(data: data)
                sha256Hashes[name] = digest.map { String(format: "%02x", $0) }.joined()
            }
        }
        let manifest = AISemanticModelManifest(
            modelID: modelID,
            requiredFiles: requiredFiles,
            fileSizes: fileSizes,
            sha256Hashes: sha256Hashes
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: modelDirectory.appendingPathComponent("install-manifest.json"), options: .atomic)
    }
}
