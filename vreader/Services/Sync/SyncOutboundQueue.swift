// Purpose: Durable outbound queue for sync operations.
// Buffers local changes for eventual push to CloudKit.
//
// Key decisions:
// - Actor-isolated for thread-safe concurrent access.
// - In-memory array backing (SwiftData backing deferred).
// - Dedup by recordType + recordID combination — re-enqueue replaces existing.
// - FIFO ordering for fairness.
// - clearAll() supports disable-sync flow.
//
// @coordinates-with: CloudKitClient.swift, SyncPipeline.swift, SyncTypes.swift

import Foundation

// MARK: - Queue Item

/// A single item in the outbound sync queue.
struct SyncOutboundQueueItem: Sendable, Identifiable, Equatable {
    let id: UUID
    let recordType: String
    let recordID: String
    let recordData: Data
    let enqueuedAt: Date
    var retryCount: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.recordType == rhs.recordType
            && lhs.recordID == rhs.recordID
            && lhs.recordData == rhs.recordData
            && lhs.enqueuedAt == rhs.enqueuedAt
            && lhs.retryCount == rhs.retryCount
    }
}

// MARK: - Dedup Key

/// Composite key for dedup: recordType + recordID.
private struct QueueDedupKey: Hashable {
    let recordType: String
    let recordID: String
}

// MARK: - Queue Actor

/// Durable outbound queue for sync records awaiting push to CloudKit.
/// Actor-isolated for safe concurrent access from multiple call sites.
actor SyncOutboundQueue {

    /// In-memory backing store. SwiftData backing deferred.
    private var items: [SyncOutboundQueueItem] = []

    /// Lookup for dedup by recordType + recordID → array index.
    private var dedupIndex: [QueueDedupKey: UUID] = [:]

    /// Number of items currently in the queue.
    var count: Int { items.count }

    // MARK: - Enqueue

    /// Adds a record to the queue. If a record with the same recordType + recordID
    /// already exists, it is replaced (dedup) with the new data.
    func enqueue(recordType: String, recordID: String, recordData: Data) {
        let key = QueueDedupKey(recordType: recordType, recordID: recordID)

        // Dedup: replace existing item with same key
        if let existingID = dedupIndex[key] {
            if let idx = items.firstIndex(where: { $0.id == existingID }) {
                let updated = SyncOutboundQueueItem(
                    id: existingID,
                    recordType: recordType,
                    recordID: recordID,
                    recordData: recordData,
                    enqueuedAt: Date(),
                    retryCount: items[idx].retryCount
                )
                items[idx] = updated
                return
            }
        }

        // New item
        let item = SyncOutboundQueueItem(
            id: UUID(),
            recordType: recordType,
            recordID: recordID,
            recordData: recordData,
            enqueuedAt: Date(),
            retryCount: 0
        )
        items.append(item)
        dedupIndex[key] = item.id
    }

    // MARK: - Dequeue

    /// Removes and returns the oldest item from the queue (FIFO).
    /// Returns nil if the queue is empty.
    func dequeue() -> SyncOutboundQueueItem? {
        guard !items.isEmpty else { return nil }
        let item = items.removeFirst()
        let key = QueueDedupKey(recordType: item.recordType, recordID: item.recordID)
        dedupIndex.removeValue(forKey: key)
        return item
    }

    // MARK: - Peek

    /// Returns the oldest item without removing it.
    /// Returns nil if the queue is empty.
    func peek() -> SyncOutboundQueueItem? {
        items.first
    }

    // MARK: - Mark Completed

    /// Removes a specific item by ID after successful upload.
    func markCompleted(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        let key = QueueDedupKey(recordType: item.recordType, recordID: item.recordID)
        // Only remove dedup entry if no newer item replaced it
        if dedupIndex[key] == id {
            dedupIndex.removeValue(forKey: key)
        }
    }

    /// Removes a batch of items by their snapshot IDs (audit fix: flush race).
    /// Only removes items whose IDs are in the set — newer re-enqueues are preserved.
    func markCompletedBatch(ids: Set<UUID>) {
        items.removeAll { item in
            guard ids.contains(item.id) else { return false }
            let key = QueueDedupKey(recordType: item.recordType, recordID: item.recordID)
            if dedupIndex[key] == item.id {
                dedupIndex.removeValue(forKey: key)
            }
            return true
        }
    }

    // MARK: - Replay

    /// Returns all pending items in FIFO order without removing them.
    /// Used for catch-up after app restart or reconnection.
    func replayPending() -> [SyncOutboundQueueItem] {
        items
    }

    // MARK: - Clear

    /// Removes all items from the queue.
    /// Used when user disables sync.
    func clearAll() {
        items.removeAll()
        dedupIndex.removeAll()
    }
}
