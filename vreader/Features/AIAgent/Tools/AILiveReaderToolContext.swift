// Purpose: Exact live reader-session dependency for Feature #177 tools.
// It resolves only (fingerprint, readerToken), never fingerprint-only fallback.

import Foundation

struct AILiveReaderDocument: Sendable {
    let snapshot: AIDocumentSnapshot
    let chunks: [AIDocumentChunk]
}

@MainActor
protocol AIReaderToolContextProviding: AnyObject, Sendable {
    var bookTitle: String { get }
    var fingerprint: DocumentFingerprint { get }
    var sessionID: AIDocumentSessionID { get }
    func resolveDocument() async -> AILiveReaderDocument?
    func tableOfContents() async -> [AIDocumentTOCSummaryItem]
}

@MainActor
final class AILiveReaderToolContext: AIReaderToolContextProviding {
    typealias TOCProvider = @MainActor @Sendable () -> [TOCEntry]

    let bookTitle: String
    let fingerprint: DocumentFingerprint
    let sessionID: AIDocumentSessionID
    private let providerResolver: any AIDocumentProviderResolving
    private let tocProvider: TOCProvider?

    init(
        bookTitle: String,
        fingerprint: DocumentFingerprint,
        readerToken: UUID,
        providerResolver: any AIDocumentProviderResolving = AIDocumentProviderRegistry.shared,
        tocProvider: TOCProvider? = nil
    ) {
        self.bookTitle = bookTitle
        self.fingerprint = fingerprint
        sessionID = AIDocumentSessionID(
            fingerprintKey: fingerprint.canonicalKey,
            readerToken: readerToken
        )
        self.providerResolver = providerResolver
        self.tocProvider = tocProvider
    }

    func resolveDocument() async -> AILiveReaderDocument? {
        guard !Task.isCancelled,
              let provider = providerResolver.resolve(session: sessionID),
              provider.bookFingerprint == fingerprint else { return nil }
        do {
            let snapshot = try await provider.snapshot()
            let chunks = try await provider.chunks()
            guard !Task.isCancelled,
                  snapshot.bookFingerprint == fingerprint,
                  let current = providerResolver.resolve(session: sessionID),
                  (current as AnyObject) === (provider as AnyObject) else { return nil }
            return AILiveReaderDocument(snapshot: snapshot, chunks: chunks)
        } catch {
            return nil
        }
    }

    func tableOfContents() async -> [AIDocumentTOCSummaryItem] {
        if let entries = tocProvider?(), !entries.isEmpty {
            return entries.map {
                AIDocumentTOCSummaryItem(
                    id: $0.id,
                    title: $0.title,
                    depth: $0.level,
                    locator: $0.locator
                )
            }
        }
        return await resolveDocument()?.snapshot.tocSummary ?? []
    }
}

enum AIReaderToolOutput {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let result = String(data: data, encoding: .utf8) else {
            throw AIError.providerError("Unable to encode structured tool output.")
        }
        return result
    }

    static func decodeLocator(_ input: JSONValue) -> Locator? {
        guard let raw = input["locator_json"]?.stringValue,
              raw.utf8.count <= 16_384,
              let data = raw.data(using: .utf8),
              let locator = try? JSONDecoder().decode(Locator.self, from: data),
              locator.validate() == nil else { return nil }
        return locator
    }

    static func boundedResult(
        _ text: String,
        maxBytes: Int,
        isError: Bool = false
    ) -> ToolResult {
        ToolResult(
            toolUseID: "",
            content: ToolResultText.clamp(text, toBytes: maxBytes),
            isError: isError
        )
    }
}

enum AICurrentReaderToolSupport {
    static func authorize(
        toolName: String,
        action: String,
        context: any AIReaderToolContextProviding,
        gate: AIAgentToolExecutionGate,
        maxBytes: Int
    ) async -> ToolResult? {
        let fingerprint = await context.fingerprint
        let outcome = await gate.authorize(AIAgentToolAuthorization.context(
            toolName: toolName,
            actionDescription: action,
            category: .readCurrentBook,
            bookFingerprintKey: fingerprint.canonicalKey
        ))
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(outcome, maxBytes: maxBytes)
        }
        return nil
    }

    static func safeContext(
        document: AILiveReaderDocument,
        scope: AIDocumentContextScope,
        boundaryCoordinator: AICurrentBookRetrievalBoundary,
        toolName: String,
        budget: Int
    ) async -> AIDocumentResolvedContext? {
        let source: [AIDocumentChunk]
        switch scope {
        case .section:
            source = document.snapshot.currentSectionChunks
        case .chapter, .bookSoFar:
            source = document.chunks
        }
        let safe = await boundaryCoordinator.authorizedTexts(
            source,
            boundary: document.snapshot.readSoFarBoundary,
            toolName: toolName,
            actionDescription: "Read structured current-book text"
        )
        guard !Task.isCancelled, !safe.isEmpty else { return nil }
        let currentSafe = safe.filter {
            $0.sourceUnitID == document.snapshot.currentSourceUnitID
        }
        let snapshot = AIDocumentSnapshot(
            bookFingerprint: document.snapshot.bookFingerprint,
            format: document.snapshot.format,
            currentLocator: document.snapshot.currentLocator,
            currentSourceUnitID: document.snapshot.currentSourceUnitID,
            currentSectionChunks: currentSafe,
            visibleChunks: currentSafe,
            currentChapterLabel: document.snapshot.currentChapterLabel,
            currentChapterBounds: document.snapshot.currentChapterBounds,
            tocSummary: document.snapshot.tocSummary,
            readSoFarBoundary: document.snapshot.readSoFarBoundary,
            exactMappingAvailable: document.snapshot.exactMappingAvailable
        )
        let resolved = AIDocumentContextResolver().resolve(
            snapshot: snapshot,
            orderedChunks: safe,
            scope: scope,
            maxUTF16: budget
        )
        return resolved.text.isEmpty ? nil : resolved
    }
}
