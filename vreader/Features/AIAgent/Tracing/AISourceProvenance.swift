// Purpose: Structured source provenance model for local retrieval, OCR, and tool results.
// Preserves book, location, snippet, retrieval method, and spoiler status without fabricating data.

import Foundation

typealias AIRetrievalMethod = AISourceRetrievalMethod

extension AISourceRetrievalMethod {
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

struct AISourceProvenance: Identifiable, Codable, Hashable, Sendable {
    /// Keeps persisted chat payloads and source chips bounded by grapheme count.
    static let maximumSnippetCharacters = 512

    let id: String
    let bookFingerprintKey: String
    let bookTitle: String
    let locator: Locator
    let sourceLabel: String?
    let chapterTitle: String?
    let pageIndex: Int?
    let href: String?
    let snippet: String
    let retrievalMethod: AISourceRetrievalMethod
    let score: Double?
    let rank: Int?
    let aheadOfReader: Bool
    let toolCallID: String?
    let mcpServerName: String?
    let isOCRDerived: Bool

    init(
        id: String = UUID().uuidString,
        bookFingerprintKey: String,
        bookTitle: String? = nil,
        locator: Locator? = nil,
        sourceLabel: String? = nil,
        chapterTitle: String? = nil,
        pageIndex: Int? = nil,
        href: String? = nil,
        snippet: String,
        retrievalMethod: AISourceRetrievalMethod,
        score: Double? = nil,
        rank: Int? = nil,
        aheadOfReader: Bool = false,
        toolCallID: String? = nil,
        mcpServerName: String? = nil,
        isOCRDerived: Bool = false
    ) {
        self.id = id
        self.bookFingerprintKey = bookFingerprintKey
        self.bookTitle = bookTitle ?? ""
        if let locator {
            self.locator = locator
        } else {
            let locs = pageIndex.map { Locator.Locations(position: $0) }
            self.locator = Locator(
                href: href ?? "",
                type: isOCRDerived ? "application/pdf" : "application/xhtml+xml",
                title: chapterTitle,
                locations: locs
            )
        }
        self.sourceLabel = sourceLabel
        self.chapterTitle = chapterTitle
        self.pageIndex = pageIndex
        self.href = href
        self.snippet = String(snippet.prefix(Self.maximumSnippetCharacters))
        self.retrievalMethod = retrievalMethod
        self.score = score
        self.rank = rank
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

        let citationID = UUID(uuidString: id) ?? UUID()
        return ChatCitation(
            id: citationID,
            sourceKind: kind,
            label: label,
            locator: locator,
            spanUTF16: nil,
            sequence: rank,
            aheadOfReader: aheadOfReader
        )
    }
}
