// Purpose: Model-facing tools for note, highlight, and bookmark mutations.
// Fully authorization-gated and idempotency-protected. All remove/delete actions always require confirmation.

import Foundation

// MARK: - Notes

struct CreateNoteTool: AITool {
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
            return AIReaderToolOutput.boundedResult("Note created with ID: \(record.id.uuidString)", maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to create note: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

struct EditNoteTool: AITool {
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
                    "content": .object(["type": .string("string"), "description": .string("The updated note text.")])
                ]),
                "required": .array([.string("note_id"), .string("content")])
            ])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        guard case .object(let dict) = input,
              case .string(let idStr)? = dict["note_id"],
              let noteID = UUID(uuidString: idStr),
              case .string(let content)? = dict["content"],
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AIReaderToolOutput.boundedResult("Valid note_id and content are required.", maxBytes: maxContentBytes, isError: true)
        }

        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Edit note \(noteID.uuidString)",
            category: .modifyAnnotations
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        do {
            try await coordinator.editNote(annotationID: noteID, content: content)
            return AIReaderToolOutput.boundedResult("Note updated successfully.", maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to edit note: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

struct DeleteNoteTool: AITool {
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
            description: "Delete an existing note. Always requires explicit user confirmation.",
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
        guard case .object(let dict) = input,
              case .string(let idStr)? = dict["note_id"],
              let noteID = UUID(uuidString: idStr) else {
            return AIReaderToolOutput.boundedResult("A valid note_id is required.", maxBytes: maxContentBytes, isError: true)
        }

        // Destructive delete: removeData category always prompts confirmation
        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Delete note \(noteID.uuidString)",
            category: .removeData
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        do {
            try await coordinator.deleteNote(annotationID: noteID)
            return AIReaderToolOutput.boundedResult("Note deleted successfully.", maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to delete note: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

// MARK: - Highlights

struct AddHighlightTool: AITool {
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
            description: "Add a highlight to the book with selected text, optional color and note.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string"), "description": .string("The passage text to highlight.")]),
                    "color": .object(["type": .string("string"), "description": .string("Color name (yellow, green, blue, pink, purple).")]),
                    "note": .object(["type": .string("string"), "description": .string("Optional note attached to highlight.")])
                ]),
                "required": .array([.string("text")])
            ])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
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
        let locator = snapshot.currentLocator ?? snapshot.readSoFarBoundary.locator
        do {
            let record = try await coordinator.addHighlight(
                bookKey: snapshot.bookFingerprint.canonicalKey,
                locator: locator,
                selectedText: text,
                color: color,
                note: note
            )
            return AIReaderToolOutput.boundedResult("Highlight created with ID: \(record.id.uuidString)", maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to add highlight: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

struct UpdateHighlightTool: AITool {
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
            description: "Update the color or attached note of an existing highlight.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "highlight_id": .object(["type": .string("string"), "description": .string("The UUID of the highlight.")]),
                    "note": .object(["type": .string("string"), "description": .string("Updated note text.")]),
                    "color": .object(["type": .string("string"), "description": .string("Updated color name.")])
                ]),
                "required": .array([.string("highlight_id")])
            ])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        guard case .object(let dict) = input,
              case .string(let idStr)? = dict["highlight_id"],
              let highlightID = UUID(uuidString: idStr) else {
            return AIReaderToolOutput.boundedResult("A valid highlight_id is required.", maxBytes: maxContentBytes, isError: true)
        }

        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Update highlight \(highlightID.uuidString)",
            category: .modifyAnnotations
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        do {
            try await coordinator.updateHighlight(
                highlightID: highlightID,
                note: dict["note"]?.stringValue,
                color: dict["color"]?.stringValue
            )
            return AIReaderToolOutput.boundedResult("Highlight updated successfully.", maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to update highlight: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

struct RemoveHighlightTool: AITool {
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
        guard case .object(let dict) = input,
              case .string(let idStr)? = dict["highlight_id"],
              let highlightID = UUID(uuidString: idStr) else {
            return AIReaderToolOutput.boundedResult("A valid highlight_id is required.", maxBytes: maxContentBytes, isError: true)
        }

        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Remove highlight \(highlightID.uuidString)",
            category: .removeData
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        do {
            try await coordinator.removeHighlight(highlightID: highlightID)
            return AIReaderToolOutput.boundedResult("Highlight removed successfully.", maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to remove highlight: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

// MARK: - Bookmarks

struct AddBookmarkTool: AITool {
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
            return AIReaderToolOutput.boundedResult("Bookmark created with ID: \(record.id.uuidString)", maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to add bookmark: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

struct UpdateBookmarkTool: AITool {
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
        guard case .object(let dict) = input,
              case .string(let idStr)? = dict["bookmark_id"],
              let bookmarkID = UUID(uuidString: idStr),
              case .string(let title)? = dict["title"] else {
            return AIReaderToolOutput.boundedResult("A valid bookmark_id and title are required.", maxBytes: maxContentBytes, isError: true)
        }

        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Update bookmark \(bookmarkID.uuidString)",
            category: .modifyAnnotations
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        do {
            try await coordinator.updateBookmark(bookmarkID: bookmarkID, title: title)
            return AIReaderToolOutput.boundedResult("Bookmark updated successfully.", maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to update bookmark: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}

struct RemoveBookmarkTool: AITool {
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
        guard case .object(let dict) = input,
              case .string(let idStr)? = dict["bookmark_id"],
              let bookmarkID = UUID(uuidString: idStr) else {
            return AIReaderToolOutput.boundedResult("A valid bookmark_id is required.", maxBytes: maxContentBytes, isError: true)
        }

        let outcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
            toolName: Self.toolName,
            action: "Remove bookmark \(bookmarkID.uuidString)",
            category: .removeData
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxContentBytes)
        }

        do {
            try await coordinator.removeBookmark(bookmarkID: bookmarkID)
            return AIReaderToolOutput.boundedResult("Bookmark removed successfully.", maxBytes: maxContentBytes)
        } catch {
            return AIReaderToolOutput.boundedResult("Failed to remove bookmark: \(error.localizedDescription)", maxBytes: maxContentBytes, isError: true)
        }
    }
}
