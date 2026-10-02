// Purpose: Model-facing tools for note mutations (create, edit, delete).
// Fully authorization-gated and idempotency-protected via AIContextualTool and AIToolMutationIdempotency.
// All destructive actions (delete/remove) require confirmation. Existing records verify ownership before mutation.

import Foundation

// MARK: - Notes

struct CreateNoteTool: AIContextualTool {
    static let toolName = "create_note"
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
            description: "Create a new note attached to the current reading location or specified passage.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "content": .object(["type": .string("string"), "description": .string("The note text content.")]),
                ]),
                "required": .array([.string("content")])
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
              case .string(let content)? = dict["content"],
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AIReaderToolOutput.boundedResult("Note content is required.", maxBytes: maxContentBytes, isError: true)
        }

        if let denied = await AICurrentReaderToolSupport.authorize(
            toolName: Self.toolName,
            action: "Create a note: \"\(content.prefix(30))...\"",
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
            let record = try await coordinator.createNote(
                bookKey: snapshot.bookFingerprint.canonicalKey,
                locator: locator,
                content: content
            )
            let summary = "Created note with ID: \(record.id.uuidString)"
            await AIToolMutationIdempotency.shared.recordCompleted(
                idempotencyKey: idempotencyKey,
                recordID: record.id.uuidString,
                summary: summary
            )
            return AIReaderToolOutput.boundedResult(summary, maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to create note: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

struct EditNoteTool: AIContextualTool {
    static let toolName = "edit_note"
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
            description: "Edit the content of an existing note.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "note_id": .object(["type": .string("string"), "description": .string("The UUID of the note to edit.")]),
                    "content": .object(["type": .string("string"), "description": .string("The new note text content.")])
                ]),
                "required": .array([.string("note_id"), .string("content")])
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
              case .string(let idStr)? = dict["note_id"],
              let noteID = UUID(uuidString: idStr),
              case .string(let content)? = dict["content"],
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AIReaderToolOutput.boundedResult("A valid note_id and content are required.", maxBytes: maxContentBytes, isError: true)
        }

        let sessionID = await context.sessionID
        let fingerprint = await context.fingerprint
        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Edit note: \"\(content.prefix(30))...\"",
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
            let isOwner = try await coordinator.verifyNoteOwnership(annotationID: noteID, bookKey: bookKey)
            guard isOwner else {
                return AIReaderToolOutput.boundedResult("Note \(noteID.uuidString) does not belong to the current book.", maxBytes: maxContentBytes, isError: true)
            }
            try await coordinator.editNote(annotationID: noteID, content: content)
            let summary = "Note updated successfully."
            await AIToolMutationIdempotency.shared.recordCompleted(
                idempotencyKey: idempotencyKey,
                recordID: noteID.uuidString,
                summary: summary
            )
            return AIReaderToolOutput.boundedResult(summary, maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to update note: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

struct DeleteNoteTool: AIContextualTool {
    static let toolName = "delete_note"
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
            description: "Delete an existing note. Always requires user confirmation.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "note_id": .object(["type": .string("string"), "description": .string("The UUID of the note to delete.")])
                ]),
                "required": .array([.string("note_id")])
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
              case .string(let idStr)? = dict["note_id"],
              let noteID = UUID(uuidString: idStr) else {
            return AIReaderToolOutput.boundedResult("A valid note_id is required.", maxBytes: maxContentBytes, isError: true)
        }

        let sessionID = await context.sessionID
        let fingerprint = await context.fingerprint
        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Delete note \(noteID.uuidString)",
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
            let isOwner = try await coordinator.verifyNoteOwnership(annotationID: noteID, bookKey: bookKey)
            guard isOwner else {
                return AIReaderToolOutput.boundedResult("Note \(noteID.uuidString) does not belong to the current book.", maxBytes: maxContentBytes, isError: true)
            }
            try await coordinator.deleteNote(annotationID: noteID)
            let summary = "Note deleted successfully."
            await AIToolMutationIdempotency.shared.recordCompleted(
                idempotencyKey: idempotencyKey,
                recordID: noteID.uuidString,
                summary: summary
            )
            return AIReaderToolOutput.boundedResult(summary, maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to delete note: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}
