// Purpose: Tests for DeviceIdentity — Keychain-backed stable device UUID.
// Uses the real Keychain in the test host (iOS Simulator).
// Each test uses a unique Keychain service to avoid cross-test pollution.

import Testing
import Foundation
@testable import vreader

@Suite("DeviceIdentity")
struct DeviceIdentityTests {

    /// Creates a DeviceIdentity backed by a unique Keychain service.
    private func makeIdentity() -> DeviceIdentity {
        let serviceId = "com.vreader.test.identity.\(UUID().uuidString)"
        return DeviceIdentity(keychainService: serviceId)
    }

    // MARK: - Basic Behavior

    @Test func returnsNonEmptyUUIDString() throws {
        let identity = makeIdentity()
        defer { identity.reset() }
        let id = identity.deviceId()
        #expect(!id.isEmpty, "deviceId should not be empty")
    }

    @Test func returnsValidUUIDFormat() throws {
        let identity = makeIdentity()
        defer { identity.reset() }
        let id = identity.deviceId()
        #expect(UUID(uuidString: id) != nil, "deviceId should be a valid UUID, got: \(id)")
    }

    @Test func returnsSameValueOnRepeatedCalls() throws {
        let identity = makeIdentity()
        defer { identity.reset() }
        let id1 = identity.deviceId()
        let id2 = identity.deviceId()
        let id3 = identity.deviceId()
        #expect(id1 == id2, "deviceId must be stable across calls")
        #expect(id2 == id3, "deviceId must be stable across calls")
    }

    // MARK: - Persistence Across Instances

    @Test func persistsAcrossInstances() throws {
        let serviceId = "com.vreader.test.identity.\(UUID().uuidString)"
        let identity1 = DeviceIdentity(keychainService: serviceId)
        let id1 = identity1.deviceId()

        // Create a new instance with the same Keychain service
        let identity2 = DeviceIdentity(keychainService: serviceId)
        let id2 = identity2.deviceId()

        #expect(id1 == id2, "deviceId must persist across instances")
        identity1.reset()
    }

    // MARK: - Reset

    @Test func resetGeneratesNewId() throws {
        let identity = makeIdentity()
        let id1 = identity.deviceId()
        identity.reset()
        let id2 = identity.deviceId()
        #expect(id1 != id2, "reset should generate a new deviceId")
        #expect(UUID(uuidString: id2) != nil, "new deviceId should be valid UUID")
        identity.reset()
    }

    // MARK: - Concurrency

    @Test func concurrentAccessReturnsSameId() async throws {
        let identity = makeIdentity()
        defer { identity.reset() }

        let ids = await withTaskGroup(of: String.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    identity.deviceId()
                }
            }
            var results: [String] = []
            for await id in group {
                results.append(id)
            }
            return results
        }

        let unique = Set(ids)
        #expect(unique.count == 1, "All concurrent callers should get the same deviceId, got \(unique.count) unique")
        #expect(UUID(uuidString: ids.first!) != nil)
    }

    // MARK: - Sendable

    @Test func deviceIdentityIsSendable() {
        let identity: any Sendable = makeIdentity()
        #expect(identity is DeviceIdentity)
    }
}
