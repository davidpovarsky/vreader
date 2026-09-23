// Purpose: Structured document context and source provenance for Feature #177.
// These values preserve exact navigation identity while text is passed through
// AI providers; flattened provider payloads must never become location truth.

import Foundation

enum AISourceRetrievalMethod: String, Codable, CaseIterable, Sendable {
    case currentContext
    case lexicalSearch
    case semanticSearch
    case annotation
    case ocr
    case wholeBookDigest
    case mcpExternal
}

enum AIReadAheadMode: String, Codable, CaseIterable, Sendable {
    case neverReadAhead = "never"
    case askBeforeReadingAhead = "ask"
    case wholeBookAllowed = "wholeBook"
}

struct AIDocumentChunk: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let bookFingerprintKey: String
    let sourceUnitID: String
    let sourceUnitIndex: Int?
    let text: String
    let locator: Locator
    let sourceLabel: String?
    let chapterTitle: String?
    let pageIndex: Int?
    let href: String?
    let localStartUTF16: Int?
    let localEndUTF16: Int?
    let globalStartUTF16: Int?
    let globalEndUTF16: Int?
    let isOCRDerived: Bool
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
    let snippet: String
    let retrievalMethod: AISourceRetrievalMethod
    let score: Double?
    let rank: Int?
    let aheadOfReader: Bool
    let toolCallID: String?
    let mcpServerName: String?

    init(
        id: String,
        bookFingerprintKey: String,
        bookTitle: String,
        locator: Locator,
        sourceLabel: String?,
        chapterTitle: String?,
        pageIndex: Int?,
        snippet: String,
        retrievalMethod: AISourceRetrievalMethod,
        score: Double?,
        rank: Int?,
        aheadOfReader: Bool,
        toolCallID: String?,
        mcpServerName: String?
    ) {
        self.id = id
        self.bookFingerprintKey = bookFingerprintKey
        self.bookTitle = bookTitle
        self.locator = locator
        self.sourceLabel = sourceLabel
        self.chapterTitle = chapterTitle
        self.pageIndex = pageIndex
        self.snippet = String(snippet.prefix(Self.maximumSnippetCharacters))
        self.retrievalMethod = retrievalMethod
        self.score = score
        self.rank = rank
        self.aheadOfReader = aheadOfReader
        self.toolCallID = toolCallID
        self.mcpServerName = mcpServerName
    }
}

struct AIDocumentTOCSummaryItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let depth: Int
    let locator: Locator
}

struct AIReadSoFarBoundary: Codable, Hashable, Sendable {
    let locator: Locator
    let sourceUnitID: String
    let sourceUnitIndex: Int?
    let localOffsetUTF16: Int?
    let globalOffsetUTF16: Int?

    init(
        locator: Locator,
        sourceUnitID: String,
        sourceUnitIndex: Int?,
        localOffsetUTF16: Int?,
        globalOffsetUTF16: Int? = nil
    ) {
        self.locator = locator
        self.sourceUnitID = sourceUnitID
        self.sourceUnitIndex = sourceUnitIndex
        self.localOffsetUTF16 = localOffsetUTF16
        self.globalOffsetUTF16 = globalOffsetUTF16
    }
}

/// Runtime reader state. ChapterBounds intentionally remains a runtime value,
/// so this snapshot does not create a persistence contract for flattened spans.
struct AIDocumentSnapshot: Sendable, Equatable {
    let bookFingerprint: DocumentFingerprint
    let format: BookFormat
    let currentLocator: Locator?
    let currentSourceUnitID: String?
    let currentSectionChunks: [AIDocumentChunk]
    let visibleChunks: [AIDocumentChunk]
    let currentChapterLabel: String?
    let currentChapterBounds: ChapterBounds?
    let tocSummary: [AIDocumentTOCSummaryItem]
    let readSoFarBoundary: AIReadSoFarBoundary
    let exactMappingAvailable: Bool
}
