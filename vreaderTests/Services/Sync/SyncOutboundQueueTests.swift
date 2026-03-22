// Purpose: Tests for SyncOutboundQueue — enqueue, dequeue, dedup, replay, count, edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("SyncOutboundQueue")
struct SyncOutboundQueueTests {

    // MARK: - Basic Enqueue / Dequeue

    @Test func enqueueAndDequeue() async {
        let queue = SyncOutboundQueue()
        let data = Data("test-record".utf8)
        await queue.enqueue(recordType: "VRBook", recordID: "book-1", recordData: data)
        let count = await queue.count
        #expect(count == 1)

        let item = await queue.dequeue()
        #expect(item != nil)
        #expect(item?.recordType == "VRBook")
        #expect(item?.recordID == "book-1")
        #expect(item?.recordData == data)
        #expect(item?.retryCount == 0)
    }

    @Test func dequeueReturnsNilWhenEmpty() async {
        let queue = SyncOutboundQueue()
        let item = await queue.dequeue()
        #expect(item == nil)
    }

    @Test func peekDoesNotRemoveItem() async {
        let queue = SyncOutboundQueue()
        await queue.enqueue(recordType: "VRBook", recordID: "book-1", recordData: Data())
        let peeked = await queue.peek()
        #expect(peeked != nil)
        let count = await queue.count
        #expect(count == 1)
    }

    @Test func peekReturnsNilWhenEmpty() async {
        let queue = SyncOutboundQueue()
        let peeked = await queue.peek()
        #expect(peeked == nil)
    }

    // MARK: - FIFO Order

    @Test func dequeueIsFIFO() async {
        let queue = SyncOutboundQueue()
        await queue.enqueue(recordType: "VRBook", recordID: "first", recordData: Data("a".utf8))
        await queue.enqueue(recordType: "VRBook", recordID: "second", recordData: Data("b".utf8))
        await queue.enqueue(recordType: "VRBook", recordID: "third", recordData: Data("c".utf8))

        let first = await queue.dequeue()
        #expect(first?.recordID == "first")
        let second = await queue.dequeue()
        #expect(second?.recordID == "second")
        let third = await queue.dequeue()
        #expect(third?.recordID == "third")
    }

    // MARK: - Mark Completed

    @Test func markCompletedRemovesItem() async {
        let queue = SyncOutboundQueue()
        await queue.enqueue(recordType: "VRBook", recordID: "book-1", recordData: Data())
        let item = await queue.peek()
        #expect(item != nil)

        await queue.markCompleted(id: item!.id)
        let count = await queue.count
        #expect(count == 0)
    }

    @Test func markCompletedWithNonexistentIdIsNoOp() async {
        let queue = SyncOutboundQueue()
        await queue.enqueue(recordType: "VRBook", recordID: "book-1", recordData: Data())
        await queue.markCompleted(id: UUID())
        let count = await queue.count
        #expect(count == 1)
    }

    // MARK: - Dedup by recordType + recordID

    @Test func dedupBySameRecordTypeAndID() async {
        let queue = SyncOutboundQueue()
        let oldData = Data("old".utf8)
        let newData = Data("new".utf8)

        await queue.enqueue(recordType: "VRBook", recordID: "book-1", recordData: oldData)
        await queue.enqueue(recordType: "VRBook", recordID: "book-1", recordData: newData)

        let count = await queue.count
        #expect(count == 1)

        let item = await queue.peek()
        #expect(item?.recordData == newData)
    }

    @Test func differentRecordTypesAreNotDeduped() async {
        let queue = SyncOutboundQueue()
        await queue.enqueue(recordType: "VRBook", recordID: "id-1", recordData: Data())
        await queue.enqueue(recordType: "VRReadingPosition", recordID: "id-1", recordData: Data())

        let count = await queue.count
        #expect(count == 2)
    }

    @Test func differentRecordIDsAreNotDeduped() async {
        let queue = SyncOutboundQueue()
        await queue.enqueue(recordType: "VRBook", recordID: "book-1", recordData: Data())
        await queue.enqueue(recordType: "VRBook", recordID: "book-2", recordData: Data())

        let count = await queue.count
        #expect(count == 2)
    }

    // MARK: - Replay Pending

    @Test func replayPendingReturnsAllItems() async {
        let queue = SyncOutboundQueue()
        await queue.enqueue(recordType: "VRBook", recordID: "book-1", recordData: Data("a".utf8))
        await queue.enqueue(recordType: "VRBook", recordID: "book-2", recordData: Data("b".utf8))
        await queue.enqueue(recordType: "VRReadingPosition", recordID: "pos-1", recordData: Data("c".utf8))

        let items = await queue.replayPending()
        #expect(items.count == 3)
        // Items should be in FIFO order
        #expect(items[0].recordID == "book-1")
        #expect(items[1].recordID == "book-2")
        #expect(items[2].recordID == "pos-1")
    }

    @Test func replayPendingReturnsEmptyWhenEmpty() async {
        let queue = SyncOutboundQueue()
        let items = await queue.replayPending()
        #expect(items.isEmpty)
    }

    @Test func replayPendingDoesNotRemoveItems() async {
        let queue = SyncOutboundQueue()
        await queue.enqueue(recordType: "VRBook", recordID: "book-1", recordData: Data())
        _ = await queue.replayPending()
        let count = await queue.count
        #expect(count == 1)
    }

    // MARK: - Count

    @Test func countReflectsQueueSize() async {
        let queue = SyncOutboundQueue()
        #expect(await queue.count == 0)

        await queue.enqueue(recordType: "VRBook", recordID: "b1", recordData: Data())
        #expect(await queue.count == 1)

        await queue.enqueue(recordType: "VRBook", recordID: "b2", recordData: Data())
        #expect(await queue.count == 2)

        _ = await queue.dequeue()
        #expect(await queue.count == 1)
    }

    // MARK: - Empty Data

    @Test func enqueueWithEmptyDataIsAllowed() async {
        let queue = SyncOutboundQueue()
        await queue.enqueue(recordType: "VRBook", recordID: "book-1", recordData: Data())
        let item = await queue.peek()
        #expect(item != nil)
        #expect(item?.recordData == Data())
    }

    // MARK: - Clear All

    @Test func clearAllRemovesEverything() async {
        let queue = SyncOutboundQueue()
        await queue.enqueue(recordType: "VRBook", recordID: "b1", recordData: Data())
        await queue.enqueue(recordType: "VRBook", recordID: "b2", recordData: Data())
        await queue.clearAll()
        #expect(await queue.count == 0)
        #expect(await queue.dequeue() == nil)
    }

    // MARK: - Enqueueing timestamps

    @Test func enqueuedAtIsSetAutomatically() async {
        let before = Date()
        let queue = SyncOutboundQueue()
        await queue.enqueue(recordType: "VRBook", recordID: "book-1", recordData: Data())
        let after = Date()
        let item = await queue.peek()
        #expect(item != nil)
        #expect(item!.enqueuedAt >= before)
        #expect(item!.enqueuedAt <= after)
    }
}
