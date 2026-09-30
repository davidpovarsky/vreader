// Purpose: Unit tests for AIToolTrace and compaction from AIToolEvent streams.
// Tests trace state updates, argument/result summarization, and call-order preservation.

import Testing
import Foundation
@testable import vreader

@Suite("AIToolTraceTests")
struct AIToolTraceTests {

    @Test func compactionCreatesOrderedTracesFromEvents() {
        let events = [
            AIToolEvent.queued(callID: "call_1", toolName: "search_current_book"),
            AIToolEvent.running(callID: "call_1", toolName: "search_current_book", argumentSummary: "query: clue"),
            AIToolEvent.queued(callID: "call_2", toolName: "create_note"),
            AIToolEvent.succeeded(callID: "call_1", toolName: "search_current_book", resultSummary: "Match found"),
            AIToolEvent.running(callID: "call_2", toolName: "create_note", argumentSummary: "title: Note 1"),
            AIToolEvent.failed(callID: "call_2", toolName: "create_note", error: "Permission denied")
        ]

        let traces = AIToolTrace.traces(from: events)

        #expect(traces.count == 2)
        #expect(traces[0].toolCallID == "call_1")
        #expect(traces[0].state == .succeeded)
        #expect(traces[0].argumentSummary == "query: clue")
        #expect(traces[0].resultSummary == "Match found")
        #expect(!traces[0].isError)

        #expect(traces[1].toolCallID == "call_2")
        #expect(traces[1].state == .failed)
        #expect(traces[1].isError)
    }

    @Test func traceCodableSerializationPreservesFields() throws {
        let trace = AIToolTrace(
            toolCallID: "c_123",
            toolName: "add_bookmark",
            displayName: "Bookmark page",
            iconName: "bookmark.fill",
            category: .mutation,
            state: .succeeded,
            argumentSummary: "page: 12",
            resultSummary: "Saved",
            isError: false,
            mutationRecordID: "bm_rec_1"
        )

        let data = try JSONEncoder().encode(trace)
        let decoded = try JSONDecoder().decode(AIToolTrace.self, from: data)

        #expect(decoded.toolCallID == trace.toolCallID)
        #expect(decoded.displayName == trace.displayName)
        #expect(decoded.state == .succeeded)
        #expect(decoded.mutationRecordID == "bm_rec_1")
    }
}
