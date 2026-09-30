// Purpose: Asynchronous event sink protocol and implementations for tool execution observability.

import Foundation

protocol AIToolEventSink: Sendable {
    func emit(_ event: AIToolEvent) async
}

struct NoOpAIToolEventSink: AIToolEventSink {
    static let shared = NoOpAIToolEventSink()
    func emit(_ event: AIToolEvent) async {}
}

actor BufferingAIToolEventSink: AIToolEventSink {
    private var buffer: [AIToolEvent] = []
    private var continuations: [UUID: AsyncStream<AIToolEvent>.Continuation] = [:]

    init() {}

    func emit(_ event: AIToolEvent) {
        buffer.append(event)
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    func allEvents() -> [AIToolEvent] {
        buffer
    }

    func clear() {
        buffer.removeAll()
    }

    func stream() -> AsyncStream<AIToolEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            for existing in buffer {
                continuation.yield(existing)
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

struct ClosureAIToolEventSink: AIToolEventSink {
    private let handler: @Sendable (AIToolEvent) async -> Void

    init(handler: @escaping @Sendable (AIToolEvent) async -> Void) {
        self.handler = handler
    }

    func emit(_ event: AIToolEvent) async {
        await handler(event)
    }
}
