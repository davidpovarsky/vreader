// Purpose: Stable device UUID persisted in Keychain. Survives app reinstall.
// Thread-safe via Keychain's atomic add-or-read pattern.
//
// Key decisions:
// - Uses kSecAttrAccessibleAfterFirstUnlock: available after first device
//   unlock, survives background sync. Different from KeychainService which
//   uses WhenUnlockedThisDeviceOnly (more restrictive, for secrets).
// - Struct-based for Sendable compliance. Keychain API is thread-safe.
// - Separate from KeychainService to keep sync identity decoupled from
//   general-purpose credential storage.
// - init accepts keychainService parameter for test isolation (unique
//   service per test avoids cross-test pollution).
//
// @coordinates-with: SyncService.swift, NSUKVSBridge.swift

import Foundation
import Security

/// Provides a stable device UUID backed by the Keychain.
struct DeviceIdentity: Sendable {

    /// The Keychain service identifier used to namespace the device ID item.
    private let serviceIdentifier: String

    /// The Keychain account name for the device ID.
    private static let account = "com.vreader.deviceId"

    // MARK: - Initialization

    /// Creates a DeviceIdentity using the given Keychain service namespace.
    ///
    /// - Parameter keychainService: A reverse-DNS string to namespace the Keychain item.
    ///   Defaults to the production sync identifier.
    init(keychainService: String = "com.vreader.sync.identity") {
        self.serviceIdentifier = keychainService
    }

    // MARK: - Public API

    /// Returns the stable device UUID. Generates a new one on first call.
    /// Thread-safe via atomic Keychain add-or-read.
    ///
    /// - Returns: A UUID string (uppercase, hyphenated).
    func deviceId() -> String {
        let newId = UUID().uuidString
        guard let data = newId.data(using: .utf8) else {
            // UTF-8 encoding of a UUID string cannot fail in practice,
            // but if it does, return the generated UUID without persisting.
            return newId
        }

        var addQuery = baseQuery()
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            // First access — we stored the new UUID.
            return newId

        case errSecDuplicateItem:
            // Already exists — read the persisted value.
            if let existing = readStoredId() {
                return existing
            }
            // Fallback: should not happen, but return the new UUID.
            return newId

        default:
            // Keychain error — return generated UUID (not persisted).
            return newId
        }
    }

    /// Deletes the stored device ID. The next call to `deviceId()` will
    /// generate a fresh UUID.
    func reset() {
        let query = baseQuery()
        _ = SecItemDelete(query as CFDictionary)
    }

    // MARK: - Private

    /// Reads the persisted device ID from the Keychain.
    private func readStoredId() -> String? {
        var query = baseQuery()
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// Builds the base Keychain query dictionary.
    private func baseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceIdentifier,
            kSecAttrAccount: Self.account,
        ]
    }
}
