// Purpose: Display metadata and safe sanitization for AI tool calls.
// Provides localized display titles, SF Symbol icons, and safe summaries
// that strictly omit secrets, passwords, or oversized raw payloads.

import Foundation

enum AIToolCategory: String, Sendable, Codable {
    case search
    case navigation
    case annotation
    case mutation
    case document
    case external
    case general

    var defaultIconName: String {
        switch self {
        case .search: return "magnifyingglass"
        case .navigation: return "arrow.right.circle"
        case .annotation: return "note.text"
        case .mutation: return "pencil.circle"
        case .document: return "doc.text"
        case .external: return "network"
        case .general: return "gearshape"
        }
    }
}

struct AIToolDisplayMetadata: Sendable, Equatable, Codable {
    let toolName: String
    let displayNameKey: String
    let defaultDisplayName: String
    let iconName: String
    let category: AIToolCategory

    static func metadata(for toolName: String) -> AIToolDisplayMetadata {
        switch toolName {
        case "search_current_book":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.search_current_book",
                defaultDisplayName: "Search current book",
                iconName: "text.magnifyingglass",
                category: .search
            )
        case "search_other_books":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.search_other_books",
                defaultDisplayName: "Search library",
                iconName: "books.vertical",
                category: .search
            )
        case "semantic_search_current_book":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.semantic_search_current_book",
                defaultDisplayName: "Semantic search in book",
                iconName: "sparkle.magnifyingglass",
                category: .search
            )
        case "semantic_search_library":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.semantic_search_library",
                defaultDisplayName: "Semantic search in library",
                iconName: "sparkles.rectangle.stack",
                category: .search
            )
        case "extract_page_text":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.extract_page_text",
                defaultDisplayName: "Extract page text (OCR)",
                iconName: "doc.viewfinder",
                category: .document
            )
        case "get_book_content":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.get_book_content",
                defaultDisplayName: "Read book content",
                iconName: "book.pages",
                category: .document
            )
        case "list_library":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.list_library",
                defaultDisplayName: "List library books",
                iconName: "books.vertical.fill",
                category: .document
            )
        case "get_current_location":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.get_current_location",
                defaultDisplayName: "Get reading location",
                iconName: "location",
                category: .navigation
            )
        case "get_current_context":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.get_current_context",
                defaultDisplayName: "Read current passage",
                iconName: "text.quote",
                category: .document
            )
        case "get_current_chapter":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.get_current_chapter",
                defaultDisplayName: "Read current chapter",
                iconName: "bookmark",
                category: .document
            )
        case "get_table_of_contents":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.get_table_of_contents",
                defaultDisplayName: "Get table of contents",
                iconName: "list.bullet.rectangle",
                category: .document
            )
        case "search_annotations":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.search_annotations",
                defaultDisplayName: "Search notes and highlights",
                iconName: "highlighter",
                category: .annotation
            )
        case "get_annotations":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.get_annotations",
                defaultDisplayName: "List annotations",
                iconName: "note.text",
                category: .annotation
            )
        case "open_location":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.open_location",
                defaultDisplayName: "Navigate to page",
                iconName: "arrow.turn.up.right",
                category: .navigation
            )
        case "open_book":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.open_book",
                defaultDisplayName: "Open book",
                iconName: "book.closed",
                category: .navigation
            )
        case "create_note":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.create_note",
                defaultDisplayName: "Add note",
                iconName: "square.and.pencil",
                category: .mutation
            )
        case "edit_note":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.edit_note",
                defaultDisplayName: "Edit note",
                iconName: "pencil.line",
                category: .mutation
            )
        case "delete_note":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.delete_note",
                defaultDisplayName: "Delete note",
                iconName: "trash",
                category: .mutation
            )
        case "add_highlight":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.add_highlight",
                defaultDisplayName: "Highlight passage",
                iconName: "highlighter",
                category: .mutation
            )
        case "update_highlight":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.update_highlight",
                defaultDisplayName: "Update highlight",
                iconName: "pencil.and.outline",
                category: .mutation
            )
        case "remove_highlight":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.remove_highlight",
                defaultDisplayName: "Remove highlight",
                iconName: "eraser",
                category: .mutation
            )
        case "add_bookmark":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.add_bookmark",
                defaultDisplayName: "Bookmark page",
                iconName: "bookmark.fill",
                category: .mutation
            )
        case "update_bookmark":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.update_bookmark",
                defaultDisplayName: "Update bookmark",
                iconName: "bookmark.square",
                category: .mutation
            )
        case "remove_bookmark":
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.remove_bookmark",
                defaultDisplayName: "Remove bookmark",
                iconName: "bookmark.slash",
                category: .mutation
            )
        default:
            if toolName.starts(with: "mcp_") {
                return AIToolDisplayMetadata(
                    toolName: toolName,
                    displayNameKey: "tool.mcp_external",
                    defaultDisplayName: toolName,
                    iconName: "network",
                    category: .external
                )
            }
            return AIToolDisplayMetadata(
                toolName: toolName,
                displayNameKey: "tool.generic",
                defaultDisplayName: toolName,
                iconName: "wrench.and.screwdriver",
                category: .general
            )
        }
    }

    /// Creates a safe bounded argument summary, removing secrets, tokens, and oversized payloads.
    static func safeArgumentSummary(for toolName: String, input: JSONValue, maxChars: Int = 120) -> String {
        switch input {
        case .object(let dict):
            var parts: [String] = []
            for (key, val) in dict.sorted(by: { $0.key < $1.key }) {
                let lowerKey = key.lowercased()
                if lowerKey.contains("token") || lowerKey.contains("secret") || lowerKey.contains("password") || lowerKey.contains("key") {
                    continue
                }
                let valStr: String
                switch val {
                case .string(let s):
                    valStr = s.count > 40 ? String(s.prefix(37)) + "..." : s
                case .number(let n):
                    valStr = "\(n)"
                case .bool(let b):
                    valStr = "\(b)"
                default:
                    valStr = "{...}"
                }
                parts.append("\(key): \(valStr)")
            }
            let combined = parts.joined(separator: ", ")
            return combined.count > maxChars ? String(combined.prefix(maxChars - 3)) + "..." : combined
        case .string(let s):
            return s.count > maxChars ? String(s.prefix(maxChars - 3)) + "..." : s
        default:
            return ""
        }
    }

    /// Creates a safe bounded result summary for UI display.
    static func safeResultSummary(_ resultText: String, isError: Bool, maxChars: Int = 140) -> String {
        let trimmed = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return isError ? "Failed" : "Completed" }
        return trimmed.count > maxChars ? String(trimmed.prefix(maxChars - 3)) + "..." : trimmed
    }
}
