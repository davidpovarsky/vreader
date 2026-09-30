// Purpose: Structured source provenance model for local retrieval, OCR, and tool results.
// Preserves book, location, snippet, retrieval method, and spoiler status without fabricating data.

import Foundation

enum AIRetrievalMethod: String, Sendable, Codable, Equatable {
    case currentContext
    case lexicalSearch
    case semanticSearch
    case annotation
    case ocr
    case wholeBookDigest
    case mcpExternal

    var defaultBadgeLabel: String {
        switch self {
        case .currentContext: return "Current"
        case .lexicalSearch: return "Exact"
        case .semanticSearch: return "Semantic"
        case .annotation: return "Note"
        case .ocr: return "OCR"
        case .wholeBookDigest: return "Digest"
        case .mcpExternal: return "External"
        }
    }
}

struct AISourceProvenance: Identifiable, Sendable, Equatable, Codable {
    let id: UUID
    let bookFingerprintKey: String
    let bookTitle: String?
    let locator: Locator?
    let sourceLabel: String?
    let chapterTitle: String?
    let pageIndex: Int?
    let href: String?
    let snippet: String
    let retrievalMethod: AIRetrievalMethod
    let score: Double?
    let aheadOfReader: Bool
    let toolCallID: String?
    let mcpServerName: String?
    let isOCRDerived: Bool

    init(
        id: UUID = UUID(),
        bookFingerprintKey: String,
        bookTitle: String? = nil,
        locator: Locator? = nil,
        sourceLabel: String? = nil,
        chapterTitle: String? = nil,
        pageIndex: Int? = nil,
        href: String? = nil,
        snippet: String,
        retrievalMethod: AIRetrievalMethod,
        score: Double? = nil,
        aheadOfReader: Bool = false,
        toolCallID: String? = nil,
        mcpServerName: String? = nil,
        isOCRDerived: Bool = false
    ) {
        self.id = id
        self.bookFingerprintKey = bookFingerprintKey
        self.bookTitle = bookTitle
        self.locator = locator
        self.sourceLabel = sourceLabel
        self.chapterTitle = chapterTitle
        self.pageIndex = pageIndex
        self.href = href
        self.snippet = snippet
        self.retrievalMethod = retrievalMethod
        self.score = score
        self.aheadOfReader = aheadOfReader
        self.toolCallID = toolCallID
        self.mcpServerName = mcpServerName
        self.isOCRDerived = isOCRDerived
    }

    /// Converts this provenance into a user-facing ChatCitation.
    func toChatCitation() -> ChatCitation {
        let label: String
        if let explicit = sourceLabel, !explicit.isEmpty {
            label = explicit
        } else if let chapter = chapterTitle, !chapter.isEmpty {
            label = chapter
        } else if let page = pageIndex {
            label = "Page \(page + 1)"
        } else {
            label = retrievalMethod.defaultBadgeLabel
        }

        let kind: ChatCitation.SourceKind
        switch retrievalMethod {
        case .annotation:
            kind = .note
        case .lexicalSearch, .semanticSearch, .ocr, .mcpExternal:
            kind = .searchResult
        case .currentContext, .wholeBookDigest:
            kind = .scope
        }

        return ChatCitation(
            id: id,
            sourceKind: kind,
            label: label,
            locator: locator,
            spanUTF16: nil,
            sequence: nil,
            aheadOfReader: aheadOfReader
        )
    }
}
