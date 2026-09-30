// Purpose: Persistent storage for non-secret MCP server profiles.

import Foundation

actor MCPServerProfileStore {
    static let shared = MCPServerProfileStore()

    private let userDefaults: UserDefaults?
    private let storageDirectory: URL?
    private let key = "vreader.mcp.serverProfiles"
    private var cachedProfiles: [MCPServerProfile] = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.storageDirectory = nil
        self.cachedProfiles = Self.load(from: userDefaults, key: key)
    }

    init(storageDirectory: URL) {
        self.userDefaults = nil
        self.storageDirectory = storageDirectory
        self.cachedProfiles = Self.load(fromDirectory: storageDirectory)
    }

    func allProfiles() -> [MCPServerProfile] {
        cachedProfiles
    }

    func profile(withID id: UUID) -> MCPServerProfile? {
        cachedProfiles.first { $0.id == id }
    }

    func saveProfile(_ profile: MCPServerProfile) throws {
        if let idx = cachedProfiles.firstIndex(where: { $0.id == profile.id }) {
            cachedProfiles[idx] = profile
        } else {
            cachedProfiles.append(profile)
        }
        try persist()
    }

    func removeProfile(withID id: UUID) {
        cachedProfiles.removeAll { $0.id == id }
        try? persist()
    }

    func deleteProfile(id: UUID) throws {
        removeProfile(withID: id)
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(cachedProfiles)
        if let storageDirectory {
            let fileURL = storageDirectory.appendingPathComponent("mcp_server_profiles.json")
            try data.write(to: fileURL, options: .atomic)
        } else if let userDefaults {
            userDefaults.set(data, forKey: key)
        }
    }

    private static func load(fromDirectory directory: URL) -> [MCPServerProfile] {
        let fileURL = directory.appendingPathComponent("mcp_server_profiles.json")
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([MCPServerProfile].self, from: data) else {
            return []
        }
        return list
    }

    private static func load(from defaults: UserDefaults, key: String) -> [MCPServerProfile] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([MCPServerProfile].self, from: data) else {
            return []
        }
        return list
    }
}
