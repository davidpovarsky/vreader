// Purpose: Persistent storage for non-secret MCP server profiles.

import Foundation

actor MCPServerProfileStore {
    static let shared = MCPServerProfileStore()

    private let userDefaults: UserDefaults
    private let key = "vreader.mcp.serverProfiles"
    private var cachedProfiles: [MCPServerProfile] = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.cachedProfiles = Self.load(from: userDefaults, key: key)
    }

    func allProfiles() -> [MCPServerProfile] {
        cachedProfiles
    }

    func profile(withID id: UUID) -> MCPServerProfile? {
        cachedProfiles.first { $0.id == id }
    }

    func saveProfile(_ profile: MCPServerProfile) {
        if let idx = cachedProfiles.firstIndex(where: { $0.id == profile.id }) {
            cachedProfiles[idx] = profile
        } else {
            cachedProfiles.append(profile)
        }
        persist()
    }

    func removeProfile(withID id: UUID) {
        cachedProfiles.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cachedProfiles) {
            userDefaults.set(data, forKey: key)
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [MCPServerProfile] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([MCPServerProfile].self, from: data) else {
            return []
        }
        return list
    }
}
