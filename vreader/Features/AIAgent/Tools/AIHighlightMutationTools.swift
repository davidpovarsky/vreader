// Purpose: Model-facing tools for highlight mutations (add, update, delete).
// Fully authorization-gated and idempotency-protected via AIContextualTool and AIToolMutationIdempotency.
// All destructive actions (delete/remove) require confirmation. Existing records verify ownership before mutation.

import Foundation

// MARK: - Highlights

struct AddHighlightTool: AIContextualTool {
    static let toolName = "add_highlight"
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
            description: "Add a highlight to the book with selected text, optional locator_json, color and note.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string"), "description": .string("The passage text to highlight.")]),
                    "locator_json": .object(["type": .string("string"), "description": .string("Optional exact JSON-encoded Locator for the passage.")]),
                    "color": .object(["type": .string("string"), "description": .string("Color name (yellow, green, blue, pink, purple).")]),
                    "note": .object(["type": .string("string"), "description": .string("Optional note attached to highlight.")])
                ]),
                "required": .array([.string("text")])
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
              case .string(let text)? = dict["text"],
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AIReaderToolOutput.boundedResult("Highlight text is required.", maxBytes: maxContentBytes, isError: true)
        }

        let color = (dict["color"]?.stringValue) ?? "yellow"
        let note = dict["note"]?.stringValue

        if let denied = await AICurrentReaderToolSupport.authorize(
            toolName: Self.toolName,
            action: "Highlight: \"\(text.prefix(30))...\"",
            context: context,
            gate: authorizationGate,
            category: .writeAnnotations,
            maxBytes: maxContentBytes
        ) { return denied }

        guard let document = await context.resolveDocument(), !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult("Active reader session unavailable.", maxBytes: maxContentBytes, isError: true)
        }

        let snapshot = document.snapshot
        guard let decoded = AIReaderToolOutput.decodeLocator(input) else {
            return AIReaderToolOutput.boundedResult(
                "A resolvable source anchor (locator_json with range or quote) is required for creating highlights. Arbitrary text cannot be highlighted at the current position.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        if !decoded.bookFingerprint.canonicalKey.isEmpty && decoded.bookFingerprint.canonicalKey != snapshot.bookFingerprint.canonicalKey {
            return AIReaderToolOutput.boundedResult(
                "Highlight locator does not match current book fingerprint.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        let locator: Locator
        let hasAnchor = (decoded.charRangeStartUTF16 != nil && decoded.charRangeEndUTF16 != nil) ||
            (decoded.textQuote != nil && !decoded.textQuote!.isEmpty) ||
            decoded.cfi != nil
        if hasAnchor {
            locator = decoded
        } else {
            return AIReaderToolOutput.boundedResult(
                "Highlight locator missing exact passage anchor.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        do {
            let record = try await coordinator.addHighlight(
                bookKey: snapshot.bookFingerprint.canonicalKey,
                locator: locator,
                selectedText: text,
                color: color,
                note: note
            )
            let summary = "Added highlight with ID: \(record.id.uuidString)"
            await AIToolMutationIdempotency.shared.recordCompleted(
                idempotencyKey: idempotencyKey,
                recordID: record.id.uuidString,
                summary: summary
            )
            return AIReaderToolOutput.boundedResult(summary, maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to add highlight: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

struct UpdateHighlightTool: AIContextualTool {
    static let toolName = "update_highlight"
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
            description: "Update the color or note of an existing highlight.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "highlight_id": .object(["type": .string("string"), "description": .string("The UUID of the highlight.")]),
                    "color": .object(["type": .string("string"), "description": .string("Optional new color name.")]),
                    "note": .object(["type": .string("string"), "description": .string("Optional new note text.")])
                ]),
                "required": .array([.string("highlight_id")])
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
              case .string(let idStr)? = dict["highlight_id"],
              let highlightID = UUID(uuidString: idStr) else {
            return AIReaderToolOutput.boundedResult("A valid highlight_id is required.", maxBytes: maxContentBytes, isError: true)
        }

        let newColor = dict["color"]?.stringValue
        let newNote = dict["note"]?.stringValue

        let sessionID = await context.sessionID
        let fingerprint = await context.fingerprint
        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Update highlight \(highlightID.uuidString)",
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
            let isOwner = try await coordinator.verifyHighlightOwnership(highlightID: highlightID, bookKey: bookKey)
            guard isOwner else {
                return AIReaderToolOutput.boundedResult("Highlight \(highlightID.uuidString) does not belong to the current book.", maxBytes: maxContentBytes, isError: true)
            }
            try await coordinator.updateHighlight(highlightID: highlightID, note: newNote, color: newColor)
            let summary = "Highlight updated successfully."
            await AIToolMutationIdempotency.shared.recordCompleted(
                idempotencyKey: idempotencyKey,
                recordID: highlightID.uuidString,
                summary: summary
            )
            return AIReaderToolOutput.boundedResult(summary, maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to update highlight: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

typealias DeleteHighlightTool = RemoveHighlightTool

struct RemoveHighlightTool: AIContextualTool {
    static let toolName = "remove_highlight"
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
            description: "Remove an existing highlight. Always requires user confirmation.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "highlight_id": .object(["type": .string("string"), "description": .string("The UUID of the highlight to remove.")])
                ]),
                "required": .array([.string("highlight_id")])
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
              case .string(let idStr)? = dict["highlight_id"],
              let highlightID = UUID(uuidString: idStr) else {
            return AIReaderToolOutput.boundedResult("A valid highlight_id is required.", maxBytes: maxContentBytes, isError: true)
        }

        let sessionID = await context.sessionID
        let fingerprint = await context.fingerprint
        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Remove highlight \(highlightID.uuidString)",
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
            let isOwner = try await coordinator.verifyHighlightOwnership(highlightID: highlightID, bookKey: bookKey)
            guard isOwner else {
                return AIReaderToolOutput.boundedResult("Highlight \(highlightID.uuidString) does not belong to the current book.", maxBytes: maxContentBytes, isError: true)
            }
            try await coordinator.removeHighlight(highlightID: highlightID)
            let summary = "Highlight removed successfully."
            await AIToolMutationIdempotency.shared.recordCompleted(
                idempotencyKey: idempotencyKey,
                recordID: highlightID.uuidString,
                summary: summary
            )
            return AIReaderToolOutput.boundedResult(summary, maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to remove highlight: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}
