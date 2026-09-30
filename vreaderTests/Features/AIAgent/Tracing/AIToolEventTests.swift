// Purpose: Unit tests for AIToolEvent lifecycle states and BufferingAIToolEventSink.
// Tests event state transitions: queued -> running -> awaitingConfirmation -> succeeded/failed/cancelled.

import Testing
import Foundation
@testable import vreader

@Suite("AIToolEventTests")
struct AIToolEventTests {

    @Test func lifecycleStateTerminalProperties() {
        #expect(AIToolLifecycleState.queued.isTerminal == false)
        #expect(AIToolLifecycleState.running.isTerminal == false)
        #expect(AIToolLifecycleState.awaitingConfirmation.isTerminal == false)
        #expect(AIToolLifecycleState.succeeded.isTerminal == true)
        #expect(AIToolLifecycleState.failed.isTerminal == true)
        #expect(AIToolLifecycleState.cancelled.isTerminal == true)
    }

    @Test func bufferingSinkCollectsAndEmitsEvents() async {
        let sink = BufferingAIToolEventSink()

        await sink.emit(AIToolEvent.queued(callID: "c1", toolName: "search_current_book"))
        await sink.emit(AIToolEvent.running(callID: "c1", toolName: "search_current_book", argumentSummary: "query: test"))
        await sink.emit(AIToolEvent.succeeded(callID: "c1", toolName: "search_current_book", resultSummary: "Found 2 matches"))

        let events = await sink.allEvents()
        #expect(events.count == 3)
        #expect(events[0].phase == .queued)
        #expect(events[1].phase == .running)
        #expect(events[2].phase == .succeeded)

        await sink.clear()
        #expect(await sink.allEvents().isEmpty)
    }
}
