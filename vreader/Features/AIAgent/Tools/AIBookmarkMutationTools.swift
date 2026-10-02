// Purpose: Model-facing tools for bookmark mutations (add, update, remove).
// Fully authorization-gated and idempotency-protected via AIContextualTool and AIToolMutationIdempotency.
// All destructive actions (delete/remove) require confirmation. Existing records verify ownership before mutation.

import Foundation

// MARK: - Bookmarks

struct AddBookmarkTool: AIContextualTool {
    static let toolName = "add_bookmark"
    let coordinator: AIAnnotationMutationCoordinator
    let context: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        coordinator: AIAnnotationMutationCoordinator,
        context: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 4_000
    ) {
        self.coordinator = coordinator
        self.context = context
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Add a bookmark to the current reading position.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "title": .object(["type": .string("string"), "description": .string("Optional bookmark title.")])
                ])
            ])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        await run(input, context: .fallback(toolCallID: UUID().uuidString))
    }

    func run(_ input: JSONValue, context execContext: AIToolExecutionContext) async -> ToolResult {
        let idempotencyKey = "\(execContext.turnID):\(execContext.toolCallID):\(Self.toolName)"
        if let cached = await AIToolMutationIdempotency.shared.outcome(idempotencyKey: idempotencyKey) {
            return AIReaderToolOutput.boundedResult(cached.summary, maxBytes: maxContentBytes)
        }

        let title: String?
        if case .object(let dict) = input {
            title = dict["title"]?.stringValue
        } else {
            title = nil
        }

        if let denied = await AICurrentReaderToolSupport.authorize(
            toolName: Self.toolName,
            action: "Add bookmark \(title.map { "\"\($0)\"" } ?? "")",
            context: context,
            gate: authorizationGate,
            category: .writeAnnotations,
            maxBytes: maxContentBytes
        ) { return denied }

        guard let document = await context.resolveDocument(), !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult("Active reader session unavailable.", maxBytes: maxContentBytes, isError: true)
        }

        let snapshot = document.snapshot
        let locator = snapshot.currentLocator ?? snapshot.readSoFarBoundary.locator
        do {
            let record = try await coordinator.addBookmark(
                bookKey: snapshot.bookFingerprint.canonicalKey,
                locator: locator,
                title: title
            )
            let summary = "Added bookmark with ID: \(record.id.uuidString)"
            await AIToolMutationIdempotency.shared.recordCompleted(
                idempotencyKey: idempotencyKey,
                recordID: record.id.uuidString,
                summary: summary
            )
            return AIReaderToolOutput.boundedResult(summary, maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to add bookmark: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

struct UpdateBookmarkTool: AIContextualTool {
    static let toolName = "update_bookmark"
    let coordinator: AIAnnotationMutationCoordinator
    let context: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        coordinator: AIAnnotationMutationCoordinator,
        context: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 4_000
    ) {
        self.coordinator = coordinator
        self.context = context
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Update the title of an existing bookmark.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bookmark_id": .object(["type": .string("string"), "description": .string("The UUID of the bookmark.")]),
                    "title": .object(["type": .string("string"), "description": .string("The new title for the bookmark.")])
                ]),
                "required": .array([.string("bookmark_id"), .string("title")])
            ])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        await run(input, context: .fallback(toolCallID: UUID().uuidString))
    }

    func run(_ input: JSONValue, context execContext: AIToolExecutionContext) async -> ToolResult {
        let idempotencyKey = "\(execContext.turnID):\(execContext.toolCallID):\(Self.toolName)"
        if let cached = await AIToolMutationIdempotency.shared.outcome(idempotencyKey: idempotencyKey) {
            return AIReaderToolOutput.boundedResult(cached.summary, maxBytes: maxContentBytes)
        }

        guard case .object(let dict) = input,
              case .string(let idStr)? = dict["bookmark_id"],
              let bookmarkID = UUID(uuidString: idStr),
              case .string(let title)? = dict["title"] else {
            return AIReaderToolOutput.boundedResult("A valid bookmark_id and title are required.", maxBytes: maxContentBytes, isError: true)
        }

        let sessionID = await context.sessionID
        let fingerprint = await context.fingerprint
        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Update bookmark \(bookmarkID.uuidString)",
            category: .modifyAnnotations,
            bookFingerprintKey: fingerprint.canonicalKey,
            readerSessionID: sessionID
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        guard let document = await context.resolveDocument(), !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult("Active reader session unavailable.", maxBytes: maxContentBytes, isError: true)
        }

        let bookKey = document.snapshot.bookFingerprint.canonicalKey
        do {
            let isOwner = try await coordinator.verifyBookmarkOwnership(bookmarkID: bookmarkID, bookKey: bookKey)
            guard isOwner else {
                return AIReaderToolOutput.boundedResult("Bookmark \(bookmarkID.uuidString) does not belong to the current book.", maxBytes: maxContentBytes, isError: true)
            }
            try await coordinator.updateBookmark(bookmarkID: bookmarkID, title: title)
            let summary = "Bookmark updated successfully."
            await AIToolMutationIdempotency.shared.recordCompleted(
                idempotencyKey: idempotencyKey,
                recordID: bookmarkID.uuidString,
                summary: summary
            )
            return AIReaderToolOutput.boundedResult(summary, maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to update bookmark: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

struct RemoveBookmarkTool: AIContextualTool {
    static let toolName = "remove_bookmark"
    let coordinator: AIAnnotationMutationCoordinator
    let context: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        coordinator: AIAnnotationMutationCoordinator,
        context: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 4_000
    ) {
        self.coordinator = coordinator
        self.context = context
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Remove an existing bookmark. Always requires user confirmation.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bookmark_id": .object(["type": .string("string"), "description": .string("The UUID of the bookmark to remove.")])
                ]),
                "required": .array([.string("bookmark_id")])
            ])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        await run(input, context: .fallback(toolCallID: UUID().uuidString))
    }

    func run(_ input: JSONValue, context execContext: AIToolExecutionContext) async -> ToolResult {
        let idempotencyKey = "\(execContext.turnID):\(execContext.toolCallID):\(Self.toolName)"
        if let cached = await AIToolMutationIdempotency.shared.outcome(idempotencyKey: idempotencyKey) {
            return AIReaderToolOutput.boundedResult(cached.summary, maxBytes: maxContentBytes)
        }

        guard case .object(let dict) = input,
              case .string(let idStr)? = dict["bookmark_id"],
              let bookmarkID = UUID(uuidString: idStr) else {
            return AIReaderToolOutput.boundedResult("A valid bookmark_id is required.", maxBytes: maxContentBytes, isError: true)
        }

        let sessionID = await context.sessionID
        let fingerprint = await context.fingerprint
        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Remove bookmark \(bookmarkID.uuidString)",
            category: .removeData,
            bookFingerprintKey: fingerprint.canonicalKey,
            readerSessionID: sessionID
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        guard let document = await context.resolveDocument(), !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult("Active reader session unavailable.", maxBytes: maxContentBytes, isError: true)
        }

        let bookKey = document.snapshot.bookFingerprint.canonicalKey
        do {
            let isOwner = try await coordinator.verifyBookmarkOwnership(bookmarkID: bookmarkID, bookKey: bookKey)
            guard isOwner else {
                return AIReaderToolOutput.boundedResult("Bookmark \(bookmarkID.uuidString) does not belong to the current book.", maxBytes: maxContentBytes, isError: true)
            }
            try await coordinator.removeBookmark(bookmarkID: bookmarkID)
            let summary = "Bookmark removed successfully."
            await AIToolMutationIdempotency.shared.recordCompleted(
                idempotencyKey: idempotencyKey,
                recordID: bookmarkID.uuidString,
                summary: summary
            )
            return AIReaderToolOutput.boundedResult(summary, maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to remove bookmark: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}
