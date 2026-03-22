// Purpose: CloudKit client abstraction for the sync engine.
// Provides a protocol for dependency injection and testing,
// plus a production implementation wrapping CKContainer/CKDatabase.
//
// Key decisions:
// - Protocol-based for DI/testing (MockCloudKitClient in tests).
// - All methods are async throws for CloudKit error propagation.
// - Lightweight record types (SyncOutboundRecord, SyncInboundRecord, SyncFetchResult)
//   decouple the pipeline from CKRecord.
// - Production impl deferred to Phase 0 entitlements spike; stub provided.
//
// @coordinates-with: SyncPipeline.swift, SyncOutboundQueue.swift, SyncTypes.swift

import Foundation

// MARK: - Lightweight Sync Record Types

/// A record to be sent to CloudKit.
struct SyncOutboundRecord: Sendable, Equatable {
    let recordType: String
    let recordID: String
    let recordData: Data
}

/// A record received from CloudKit.
/// Fields are String-keyed with String values. Complex types (Data, Date)
/// are serialized to String before storage. This avoids Sendable issues with `Any`.
struct SyncInboundRecord: Sendable, Equatable {
    let recordType: String
    let recordID: String
    let fields: [String: String]
}

/// Result of a fetch-changes operation.
struct SyncFetchResult: Sendable {
    let records: [SyncInboundRecord]
    let newChangeToken: Data?
}

// MARK: - Protocol

/// CloudKit client abstraction for sync operations.
/// Conforming types must be Sendable for safe cross-actor use.
protocol CloudKitClientProtocol: Sendable {

    /// Saves records to CloudKit.
    /// - Parameter records: The outbound records to save.
    /// - Throws: On network/auth/quota errors.
    func saveRecords(_ records: [SyncOutboundRecord]) async throws

    /// Fetches changes from a CloudKit zone since the given change token.
    /// - Parameters:
    ///   - zoneID: The zone identifier (e.g., "VReaderData").
    ///   - changeToken: The last known server change token, or nil for a full fetch.
    /// - Returns: Changed records and a new change token.
    /// - Throws: On network/auth errors.
    func fetchChanges(zoneID: String, changeToken: Data?) async throws -> SyncFetchResult

    /// Creates a custom record zone (idempotent).
    /// - Parameter zoneID: The zone identifier to create.
    /// - Throws: On network/auth errors.
    func createZone(zoneID: String) async throws

    /// Registers a push subscription for zone changes.
    /// - Parameter zoneID: The zone identifier to subscribe to.
    /// - Throws: On network/auth errors.
    func subscribe(zoneID: String) async throws
}

// MARK: - Production Implementation (Stub)

/// Production CloudKit client wrapping CKContainer/CKDatabase.
/// Full implementation deferred to WI-000 (entitlements spike).
/// Currently throws `.syncDisabled` for all operations.
final class CloudKitClient: CloudKitClientProtocol, Sendable {

    // Container identifier for VReader's private CloudKit database.
    static let containerID = "iCloud.com.vreader.app"

    func saveRecords(_ records: [SyncOutboundRecord]) async throws {
        throw SyncError.syncDisabled
    }

    func fetchChanges(zoneID: String, changeToken: Data?) async throws -> SyncFetchResult {
        throw SyncError.syncDisabled
    }

    func createZone(zoneID: String) async throws {
        throw SyncError.syncDisabled
    }

    func subscribe(zoneID: String) async throws {
        throw SyncError.syncDisabled
    }
}
