// Purpose: Orchestrates the sync pipeline — enqueue outbound changes,
// flush to CloudKit, fetch inbound changes, and process them.
//
// Key decisions:
// - Actor-isolated for thread-safe operation.
// - Injected CloudKitClientProtocol for testability (mock in tests).
// - Delegates conflict resolution to SyncConflictResolver.
// - processInbound is a Phase 1 stub (stores records for future apply logic).
// - Flush sends all queued records in a single batch to the CK client.
// - On flush error, queue is preserved for retry.
// - Change tokens are managed via ChangeTokenStore for incremental fetches.
//
// @coordinates-with: CloudKitClient.swift, SyncOutboundQueue.swift,
//   ChangeTokenStore.swift, SyncConflictResolver.swift, SyncTypes.swift

import Foundation

/// Orchestrates the sync pipeline: enqueue, flush, fetch, and process.
actor SyncPipeline {

    // MARK: - Dependencies

    private let client: any CloudKitClientProtocol
    private let conflictResolver: SyncConflictResolver
    private let queue: SyncOutboundQueue
    private let tokenStore: ChangeTokenStore

    // MARK: - Init

    /// Creates a sync pipeline with injected dependencies.
    /// - Parameters:
    ///   - client: The CloudKit client (protocol, for testability).
    ///   - conflictResolver: Conflict resolution logic.
    ///   - queue: The outbound record queue.
    ///   - tokenStore: Change token persistence.
    init(
        client: any CloudKitClientProtocol,
        conflictResolver: SyncConflictResolver = SyncConflictResolver(),
        queue: SyncOutboundQueue = SyncOutboundQueue(),
        tokenStore: ChangeTokenStore = ChangeTokenStore()
    ) {
        self.client = client
        self.conflictResolver = conflictResolver
        self.queue = queue
        self.tokenStore = tokenStore
    }

    // MARK: - Outbound

    /// Number of items pending in the outbound queue.
    var pendingCount: Int {
        get async { await queue.count }
    }

    /// Adds a record to the outbound queue for eventual push to CloudKit.
    /// - Parameters:
    ///   - recordType: The CK record type (e.g., "VRBook").
    ///   - recordID: The unique record identifier.
    ///   - recordData: Serialized record data.
    func enqueue(recordType: String, recordID: String, recordData: Data) async {
        await queue.enqueue(recordType: recordType, recordID: recordID, recordData: recordData)
    }

    /// Sends all queued records to CloudKit via the client.
    /// On success, clears the queue. On error, queue is preserved for retry.
    /// - Throws: Propagates client errors (network, auth, quota).
    func flush() async throws {
        let pending = await queue.replayPending()
        guard !pending.isEmpty else { return }

        let outboundRecords = pending.map { item in
            SyncOutboundRecord(
                recordType: item.recordType,
                recordID: item.recordID,
                recordData: item.recordData
            )
        }

        try await client.saveRecords(outboundRecords)

        // Only clear on success
        for item in pending {
            await queue.markCompleted(id: item.id)
        }
    }

    // MARK: - Inbound

    /// Fetches changes from CloudKit since the last stored change token.
    /// Stores the new token on success.
    /// - Parameter zoneID: The zone to fetch changes from.
    /// - Returns: The inbound records received.
    /// - Throws: Propagates client errors.
    func fetchChanges(zoneID: String) async throws -> [SyncInboundRecord] {
        let currentToken = tokenStore.load(forZone: zoneID)
        let result = try await client.fetchChanges(zoneID: zoneID, changeToken: currentToken)

        // Save the new token only on success
        if let newToken = result.newChangeToken {
            tokenStore.save(token: newToken, forZone: zoneID)
        }

        return result.records
    }

    /// Processes inbound records (Phase 1 stub).
    /// In later phases, this will resolve conflicts and apply changes via PersistenceActor.
    /// - Parameter records: The inbound records to process.
    /// - Returns: The number of records processed (for status reporting).
    func processInbound(records: [SyncInboundRecord]) -> Int {
        // Phase 1 stub: just count. Conflict resolution + apply deferred.
        records.count
    }

    // MARK: - Zone Management

    /// Creates a custom record zone (idempotent). Delegates to the CK client.
    /// - Parameter zoneID: The zone identifier to create.
    func createZone(zoneID: String) async throws {
        try await client.createZone(zoneID: zoneID)
    }

    /// Registers a push subscription for zone changes.
    /// - Parameter zoneID: The zone to subscribe to.
    func subscribe(zoneID: String) async throws {
        try await client.subscribe(zoneID: zoneID)
    }
}
