// Purpose: Unit tests for ChatSessionPayload v1 -> v2 migration with tool traces.
// Proves backward-compatible decoding of legacy v1 sessions without toolTraces.

import Testing
import Foundation
@testable import vreader

@Suite("ChatSessionToolTraceMigrationTests")
struct ChatSessionToolTraceMigrationTests {

    @Test func legacyV1PayloadDecodesCleanlyWithEmptyToolTraces() throws {
        let v1JSON = """
        {
            "version": 1,
            "id": "11111111-2222-3333-4444-555555555555",
            "bookFingerprint": "book-fingerprint-v1",
            "title": "Legacy Session",
            "createdAt": "2026-01-01T12:00:00Z",
            "updatedAt": "2026-01-01T12:05:00Z",
            "messages": [
                {
                    "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                    "role": "user",
                    "content": "What is this book about?",
                    "timestamp": "2026-01-01T12:00:00Z",
                    "citations": []
                },
                {
                    "id": "ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj",
                    "role": "assistant",
                    "content": "This is an adventure book.",
                    "timestamp": "2026-01-01T12:01:00Z",
                    "citations": []
                }
            ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ChatSessionPayload.self, from: Data(v1JSON.utf8))

        #expect(payload.version == 1)
        #expect(payload.title == "Legacy Session")
        #expect(payload.messages.count == 2)
        #expect(payload.messages[0].toolTraces.isEmpty)
        #expect(payload.messages[1].toolTraces.isEmpty)
    }

    @Test func v2PayloadEncodesAndDecodesToolTracesRoundTrip() throws {
        let trace = AIToolTrace(
            toolCallID: "call_search_1",
            toolName: "semantic_search_current_book",
            displayName: "Semantic search in book",
            iconName: "sparkle.magnifyingglass",
            category: .search,
            state: .succeeded,
            argumentSummary: "query: golden key",
            resultSummary: "1 result found",
            isError: false
        )

        let msg = PersistedChatMessage(
            id: UUID(),
            role: "assistant",
            content: "I found the passage about the key.",
            timestamp: Date(),
            citations: [],
            toolTraces: [trace]
        )

        let payload = ChatSessionPayload(
            version: ChatSessionPayload.currentVersion,
            id: UUID(),
            bookFingerprint: "book-fingerprint-v2",
            title: "Session With Tools",
            createdAt: Date(),
            updatedAt: Date(),
            messages: [msg]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ChatSessionPayload.self, from: data)

        #expect(decoded.version == 2)
        #expect(decoded.messages.count == 1)
        #expect(decoded.messages[0].toolTraces.count == 1)
        #expect(decoded.messages[0].toolTraces[0].toolName == "semantic_search_current_book")
    }
}
