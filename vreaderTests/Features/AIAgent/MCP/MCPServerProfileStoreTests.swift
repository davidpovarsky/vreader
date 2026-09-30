// Purpose: Unit tests for MCPServerProfileStore and MCPServerProfile.
// Tests profile CRUD, profile security validation (HTTPS enforcement), and endpoint updates.

import Testing
import Foundation
@testable import vreader

@Suite("MCPServerProfileStoreTests")
struct MCPServerProfileStoreTests {

    @Test func profileEnforcesSecureEndpoint() {
        let insecure = MCPServerProfile(
            name: "Insecure Server",
            endpointURL: URL(string: "http://external.example.com/mcp")!
        )
        #expect(insecure.isSecureEndpoint == false)

        let secure = MCPServerProfile(
            name: "Secure Server",
            endpointURL: URL(string: "https://secure.example.com/mcp")!
        )
        #expect(secure.isSecureEndpoint == true)

        let loopback = MCPServerProfile(
            name: "Local Dev Server",
            endpointURL: URL(string: "http://localhost:8080/mcp")!
        )
        #expect(loopback.isSecureEndpoint == true)
    }

    @Test func profileStoreSavesAndLoadsProfiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MCPServerProfileStore(storageDirectory: tempDir)
        let profile = MCPServerProfile(
            id: UUID(),
            name: "My Server",
            endpointURL: URL(string: "https://api.example.com/mcp")!,
            isEnabled: true
        )

        try await store.saveProfile(profile)
        let loaded = await store.allProfiles()

        #expect(loaded.count == 1)
        #expect(loaded[0].name == "My Server")
        #expect(loaded[0].endpointURL == URL(string: "https://api.example.com/mcp")!)

        try await store.deleteProfile(id: profile.id)
        let afterDelete = await store.allProfiles()
        #expect(afterDelete.isEmpty)
    }
}
