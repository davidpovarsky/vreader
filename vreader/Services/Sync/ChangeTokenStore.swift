// Purpose: Persists CloudKit server change tokens in UserDefaults.
// Enables incremental fetch after app restart — avoids full zone re-fetch.
//
// Key decisions:
// - UserDefaults backing for simplicity and durability across app restarts.
// - Key prefix "ck_changeToken_" isolates sync tokens from other defaults.
// - Injectable UserDefaults for test isolation (suite-based).
// - Final class with @unchecked Sendable (UserDefaults is thread-safe but not Sendable).
//
// @coordinates-with: CloudKitClient.swift, SyncPipeline.swift

import Foundation

/// Persists CloudKit server change tokens per zone in UserDefaults.
/// UserDefaults is thread-safe but not marked Sendable; @unchecked is appropriate.
final class ChangeTokenStore: @unchecked Sendable {

    /// Key prefix for change token storage.
    private static let keyPrefix = "ck_changeToken_"

    /// The UserDefaults instance used for persistence.
    private let defaults: UserDefaults

    // MARK: - Init

    /// Creates a change token store backed by the given UserDefaults.
    /// - Parameter defaults: The UserDefaults suite. Defaults to `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Save

    /// Saves a change token for the specified zone.
    /// - Parameters:
    ///   - token: The serialized server change token data.
    ///   - zone: The zone identifier (e.g., "VReaderData").
    func save(token: Data, forZone zone: String) {
        defaults.set(token, forKey: key(for: zone))
    }

    // MARK: - Load

    /// Loads the stored change token for the specified zone.
    /// - Parameter zone: The zone identifier.
    /// - Returns: The token data, or nil if no token has been stored (first use).
    func load(forZone zone: String) -> Data? {
        defaults.data(forKey: key(for: zone))
    }

    // MARK: - Clear

    /// Removes the stored change token for the specified zone.
    /// No-op if no token exists for the zone.
    /// - Parameter zone: The zone identifier.
    func clear(forZone zone: String) {
        defaults.removeObject(forKey: key(for: zone))
    }

    // MARK: - Private

    /// Constructs the UserDefaults key for a given zone.
    private func key(for zone: String) -> String {
        Self.keyPrefix + zone
    }
}
