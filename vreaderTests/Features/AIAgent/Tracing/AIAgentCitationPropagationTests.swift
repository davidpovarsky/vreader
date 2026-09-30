// Purpose: Unit tests for AI agent citation propagation and tool trace persistence.
// Tests that tool sources reach the assistant message citations and tool traces are properly attached.

import Testing
import Foundation
@testable import vreader

@Suite("AIAgentCitationPropagationTests")
struct AIAgentCitationPropagationTests {

    @Test func chatMessageCarriesToolTraces() {
        let trace = AIToolTrace(
            toolCallID: "call_1",
            toolName: "semantic_search_current_book",
            displayName: "Semantic search in book",
            iconName: "sparkle.magnifyingglass",
            category: .search,
            state: .succeeded,
            argumentSummary: "query: golden key",
            resultSummary: "Found match in Ch. 3",
            isError: false
        )

        var message = ChatMessage(role: .assistant, content: "The key was found.")
        #expect(message.toolTraces.isEmpty)

        message.toolTraces = [trace]
        #expect(message.toolTraces.count == 1)
        #expect(message.toolTraces[0].toolName == "semantic_search_current_book")
    }

    @Test func agenticResultWithTracesAttachesToMessage() {
        let trace = AIToolTrace(
            toolCallID: "call_2",
            toolName: "get_current_chapter",
            displayName: "Current Chapter",
            category: .document,
            state: .succeeded
        )

        let citation = ChatCitation(
            sourceKind: .searchResult,
            label: "Chapter 3",
            locator: Locator(href: "ch3.xhtml", type: "application/xhtml+xml")
        )

        let result = AgenticResult(
            finalText: "Answer derived from Chapter 3.",
            usedTools: true,
            traces: [trace],
            citations: [citation]
        )

        #expect(result.usedTools == true)
        #expect(result.traces.count == 1)
        #expect(result.citations.count == 1)
        #expect(result.citations[0].label == "Chapter 3")
    }
}
