// Purpose: Tests for SyncPipeline — enqueue→flush with mock CK client,
// fetchChanges with token, processInbound stub, error propagation.

import Testing
import Foundation
@testable import vreader

// MARK: - Mock CloudKit Client

/// Mock CloudKit client for unit testing the sync pipeline.
/// Records all calls for verification; configurable responses.
final class MockCloudKitClient: CloudKitClientProtocol, @unchecked Sendable {

    // MARK: - Call Recording

    struct SavedRecord: Sendable {
        let recordType: String
        let recordID: String
        let data: Data
    }

    private(set) var savedRecords: [SavedRecord] = []
    private(set) var fetchChangesCalls: [(zoneID: String, changeToken: Data?)] = []
    private(set) var createZoneCalls: [String] = []
    private(set) var subscribeCalls: [String] = []

    // MARK: - Configurable Responses

    var saveRecordsError: Error?
    var fetchChangesResult: [SyncInboundRecord] = []
    var fetchChangesNewToken: Data?
    var fetchChangesError: Error?
    var createZoneError: Error?
    var subscribeError: Error?

    // MARK: - Protocol Conformance

    func saveRecords(_ records: [SyncOutboundRecord]) async throws {
        if let error = saveRecordsError { throw error }
        for record in records {
            savedRecords.append(SavedRecord(
                recordType: record.recordType,
                recordID: record.recordID,
                data: record.recordData
            ))
        }
    }

    func fetchChanges(
        zoneID: String,
        changeToken: Data?
    ) async throws -> SyncFetchResult {
        fetchChangesCalls.append((zoneID: zoneID, changeToken: changeToken))
        if let error = fetchChangesError { throw error }
        return SyncFetchResult(
            records: fetchChangesResult,
            newChangeToken: fetchChangesNewToken
        )
    }

    func createZone(zoneID: String) async throws {
        createZoneCalls.append(zoneID)
        if let error = createZoneError { throw error }
    }

    func subscribe(zoneID: String) async throws {
        subscribeCalls.append(zoneID)
        if let error = subscribeError { throw error }
    }
}

// MARK: - Tests

@Suite("SyncPipeline")
struct SyncPipelineTests {

    private func makePipeline(
        client: MockCloudKitClient = MockCloudKitClient(),
        resolver: SyncConflictResolver = SyncConflictResolver(),
        tokenStore: ChangeTokenStore? = nil
    ) -> (SyncPipeline, MockCloudKitClient, ChangeTokenStore) {
        let defaults = UserDefaults(suiteName: "com.vreader.test.pipeline.\(UUID().uuidString)")!
        let ts = tokenStore ?? ChangeTokenStore(defaults: defaults)
        let pipeline = SyncPipeline(
            client: client,
            conflictResolver: resolver,
            queue: SyncOutboundQueue(),
            tokenStore: ts
        )
        return (pipeline, client, ts)
    }

    // MARK: - Enqueue

    @Test func enqueueAddsToQueue() async {
        let (pipeline, _, _) = makePipeline()
        await pipeline.enqueue(recordType: "VRBook", recordID: "book-1", recordData: Data("test".utf8))
        let pendingCount = await pipeline.pendingCount
        #expect(pendingCount == 1)
    }

    @Test func enqueueMultipleItems() async {
        let (pipeline, _, _) = makePipeline()
        await pipeline.enqueue(recordType: "VRBook", recordID: "b1", recordData: Data())
        await pipeline.enqueue(recordType: "VRReadingPosition", recordID: "p1", recordData: Data())
        let pendingCount = await pipeline.pendingCount
        #expect(pendingCount == 2)
    }

    // MARK: - Flush

    @Test func flushSendsAllQueuedRecords() async throws {
        let client = MockCloudKitClient()
        let (pipeline, _, _) = makePipeline(client: client)

        await pipeline.enqueue(recordType: "VRBook", recordID: "b1", recordData: Data("book".utf8))
        await pipeline.enqueue(recordType: "VRReadingPosition", recordID: "p1", recordData: Data("pos".utf8))

        try await pipeline.flush()

        #expect(client.savedRecords.count == 2)
        #expect(client.savedRecords[0].recordType == "VRBook")
        #expect(client.savedRecords[1].recordType == "VRReadingPosition")
    }

    @Test func flushClearsQueueOnSuccess() async throws {
        let client = MockCloudKitClient()
        let (pipeline, _, _) = makePipeline(client: client)

        await pipeline.enqueue(recordType: "VRBook", recordID: "b1", recordData: Data())
        try await pipeline.flush()

        let pendingCount = await pipeline.pendingCount
        #expect(pendingCount == 0)
    }

    @Test func flushWithEmptyQueueIsNoOp() async throws {
        let client = MockCloudKitClient()
        let (pipeline, _, _) = makePipeline(client: client)
        try await pipeline.flush()
        #expect(client.savedRecords.isEmpty)
    }

    @Test func flushPropagatesClientError() async {
        let client = MockCloudKitClient()
        client.saveRecordsError = SyncError.networkUnavailable
        let (pipeline, _, _) = makePipeline(client: client)

        await pipeline.enqueue(recordType: "VRBook", recordID: "b1", recordData: Data())

        do {
            try await pipeline.flush()
            Issue.record("Expected flush to throw")
        } catch {
            // Error propagated correctly
        }
    }

    @Test func flushRetainsQueueOnError() async {
        let client = MockCloudKitClient()
        client.saveRecordsError = SyncError.networkUnavailable
        let (pipeline, _, _) = makePipeline(client: client)

        await pipeline.enqueue(recordType: "VRBook", recordID: "b1", recordData: Data())
        try? await pipeline.flush()

        let pendingCount = await pipeline.pendingCount
        #expect(pendingCount == 1)
    }

    // MARK: - Fetch Changes

    @Test func fetchChangesUsesStoredToken() async throws {
        let client = MockCloudKitClient()
        let defaults = UserDefaults(suiteName: "com.vreader.test.pipeline.\(UUID().uuidString)")!
        let tokenStore = ChangeTokenStore(defaults: defaults)
        let existingToken = Data("existing-token".utf8)
        tokenStore.save(token: existingToken, forZone: "VReaderData")

        let (pipeline, _, _) = makePipeline(client: client, tokenStore: tokenStore)
        _ = try await pipeline.fetchChanges(zoneID: "VReaderData")

        #expect(client.fetchChangesCalls.count == 1)
        #expect(client.fetchChangesCalls[0].changeToken == existingToken)
    }

    @Test func fetchChangesPassesNilTokenOnFirstUse() async throws {
        let client = MockCloudKitClient()
        let (pipeline, _, _) = makePipeline(client: client)

        _ = try await pipeline.fetchChanges(zoneID: "VReaderData")

        #expect(client.fetchChangesCalls.count == 1)
        #expect(client.fetchChangesCalls[0].changeToken == nil)
    }

    @Test func fetchChangesSavesNewToken() async throws {
        let client = MockCloudKitClient()
        let newToken = Data("new-server-token".utf8)
        client.fetchChangesNewToken = newToken

        let defaults = UserDefaults(suiteName: "com.vreader.test.pipeline.\(UUID().uuidString)")!
        let tokenStore = ChangeTokenStore(defaults: defaults)
        let (pipeline, _, _) = makePipeline(client: client, tokenStore: tokenStore)

        _ = try await pipeline.fetchChanges(zoneID: "VReaderData")

        let storedToken = tokenStore.load(forZone: "VReaderData")
        #expect(storedToken == newToken)
    }

    @Test func fetchChangesReturnsInboundRecords() async throws {
        let client = MockCloudKitClient()
        let record = SyncInboundRecord(
            recordType: "VRBook",
            recordID: "book-1",
            fields: ["title": "Test Book"]
        )
        client.fetchChangesResult = [record]

        let (pipeline, _, _) = makePipeline(client: client)
        let result = try await pipeline.fetchChanges(zoneID: "VReaderData")

        #expect(result.count == 1)
        #expect(result[0].recordType == "VRBook")
        #expect(result[0].recordID == "book-1")
    }

    @Test func fetchChangesPropagatesError() async {
        let client = MockCloudKitClient()
        client.fetchChangesError = SyncError.networkUnavailable

        let (pipeline, _, _) = makePipeline(client: client)

        do {
            _ = try await pipeline.fetchChanges(zoneID: "VReaderData")
            Issue.record("Expected fetchChanges to throw")
        } catch {
            // Error propagated correctly
        }
    }

    @Test func fetchChangesDoesNotSaveTokenOnError() async {
        let client = MockCloudKitClient()
        client.fetchChangesError = SyncError.networkUnavailable

        let defaults = UserDefaults(suiteName: "com.vreader.test.pipeline.\(UUID().uuidString)")!
        let tokenStore = ChangeTokenStore(defaults: defaults)
        let (pipeline, _, _) = makePipeline(client: client, tokenStore: tokenStore)

        try? await pipeline.fetchChanges(zoneID: "VReaderData")

        let stored = tokenStore.load(forZone: "VReaderData")
        #expect(stored == nil)
    }

    // MARK: - Process Inbound (Phase 1 stub)

    @Test func processInboundReturnsRecordCount() async {
        let (pipeline, _, _) = makePipeline()
        let records = [
            SyncInboundRecord(recordType: "VRBook", recordID: "b1", fields: [:]),
            SyncInboundRecord(recordType: "VRBook", recordID: "b2", fields: [:]),
        ]
        let count = await pipeline.processInbound(records: records)
        #expect(count == 2)
    }

    @Test func processInboundEmptyRecordsReturnsZero() async {
        let (pipeline, _, _) = makePipeline()
        let count = await pipeline.processInbound(records: [])
        #expect(count == 0)
    }

    // MARK: - Create Zone

    @Test func createZoneCallsClient() async throws {
        let client = MockCloudKitClient()
        let (pipeline, _, _) = makePipeline(client: client)
        try await pipeline.createZone(zoneID: "VReaderData")
        #expect(client.createZoneCalls == ["VReaderData"])
    }

    // MARK: - Subscribe

    @Test func subscribeCallsClient() async throws {
        let client = MockCloudKitClient()
        let (pipeline, _, _) = makePipeline(client: client)
        try await pipeline.subscribe(zoneID: "VReaderData")
        #expect(client.subscribeCalls == ["VReaderData"])
    }
}
