// Purpose: Shared target resolution, boundary filtering, and deterministic
// formatting for the read-only annotation tools.

import Foundation

struct AIAnnotationToolItem: Sendable {
    let id: UUID
    let kind: String
    let text: String
    let locator: Locator
    let sortDate: Date
}

enum AIAnnotationReadSupport {
    enum TargetResolution: Sendable {
        case success(Target)
        case failure(String)
    }

    struct Target: Sendable {
        let fingerprintKey: String
        let isCurrentBook: Bool
        let title: String
    }

    static func resolveTarget(
        input: JSONValue,
        bookResolver: any BookContentProvider,
        readerContext: any AIReaderToolContextProviding
    ) async -> TargetResolution {
        let currentTitle = await readerContext.bookTitle
        let currentFingerprint = await readerContext.fingerprint
        let currentKey = currentFingerprint.canonicalKey
        guard let requested = input["book_title"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !requested.isEmpty else {
            return .success(Target(
                fingerprintKey: currentKey,
                isCurrentBook: true,
                title: currentTitle
            ))
        }
        switch await bookResolver.findBook(title: requested) {
        case .notFound:
            return .failure("No book titled \"\(ToolResultText.oneLine(requested, maxChars: 120))\" is in the library.")
        case .ambiguous:
            return .failure("Several books match that title; provide an unambiguous book title.")
        case .found(let info):
            return .success(Target(
                fingerprintKey: info.fingerprintKey,
                isCurrentBook: info.fingerprintKey == currentKey,
                title: info.title
            ))
        }
    }

    static func items(_ collection: AIAnnotationCollection) -> [AIAnnotationToolItem] {
        let notes = collection.notes.map {
            AIAnnotationToolItem(
                id: $0.annotationId,
                kind: "note",
                text: $0.content,
                locator: $0.locator,
                sortDate: $0.updatedAt
            )
        }
        let highlights = collection.highlights.map {
            let note = ($0.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let text = note.isEmpty ? $0.selectedText : "\($0.selectedText) — note: \(note)"
            return AIAnnotationToolItem(
                id: $0.highlightId,
                kind: "highlight",
                text: text,
                locator: $0.locator,
                sortDate: $0.updatedAt
            )
        }
        let bookmarks = collection.bookmarks.map {
            AIAnnotationToolItem(
                id: $0.bookmarkId,
                kind: "bookmark",
                text: $0.title ?? "Bookmark",
                locator: $0.locator,
                sortDate: $0.updatedAt
            )
        }
        return (notes + highlights + bookmarks).sorted {
            if $0.sortDate != $1.sortDate { return $0.sortDate > $1.sortDate }
            if $0.kind != $1.kind { return $0.kind < $1.kind }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func authorizedCurrentItems(
        _ items: [AIAnnotationToolItem],
        context: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        toolName: String
    ) async -> [AIAnnotationToolItem]? {
        guard let document = await context.resolveDocument() else { return nil }
        let coordinator = AICurrentBookRetrievalBoundary(
            authorizationGate: authorizationGate
        )
        var safe: [AIAnnotationToolItem] = []
        for item in items {
            guard !Task.isCancelled else { return nil }
            let candidate = candidate(for: item, chunks: document.chunks)
            if await coordinator.authorizedText(
                candidate,
                boundary: document.snapshot.readSoFarBoundary,
                toolName: toolName,
                actionDescription: "Read an annotation attached to current-book content",
                overlapPolicy: .atomic
            ) != nil {
                safe.append(item)
            }
        }
        return safe
    }

    static func formatted(
        _ items: [AIAnnotationToolItem],
        total: Int,
        title: String,
        maxTextCharacters: Int,
        maxBytes: Int
    ) -> String {
        guard !items.isEmpty else {
            return ToolResultText.clamp(
                "No authorized annotations for \"\(ToolResultText.oneLine(title, maxChars: 120))\".",
                toBytes: maxBytes
            )
        }
        var lines = [items.count < total
            ? "Showing \(items.count) of \(total) annotations for \"\(ToolResultText.oneLine(title, maxChars: 120))\":"
            : "\(items.count) annotation(s) for \"\(ToolResultText.oneLine(title, maxChars: 120))\":" ]
        for item in items {
            let locator = (try? AIReaderToolOutput.encode(item.locator)) ?? "{}"
            lines.append(
                "- id=\(item.id.uuidString) kind=\(item.kind) text=\(ToolResultText.oneLine(item.text, maxChars: maxTextCharacters)) locator_json=\(locator)"
            )
        }
        return ToolResultText.clamp(lines.joined(separator: "\n"), toBytes: maxBytes)
    }

    private static func candidate(
        for item: AIAnnotationToolItem,
        chunks: [AIDocumentChunk]
    ) -> AIDocumentChunk {
        let locator = item.locator
        let source = chunks.first { chunk in
            if let page = locator.page {
                return (chunk.pageIndex ?? chunk.locator.page) == page
            }
            if let href = locator.href {
                return (chunk.href ?? chunk.locator.href) == href
            }
            if let offset = locator.charRangeStartUTF16 ?? locator.charOffsetUTF16,
               let start = chunk.globalStartUTF16,
               let end = chunk.globalEndUTF16 {
                return start <= offset && offset <= end
            }
            return false
        }
        let globalStart = locator.charRangeStartUTF16 ?? locator.charOffsetUTF16
        let globalEnd = locator.charRangeEndUTF16 ?? globalStart.map { $0 + 1 }
        let localStart = globalStart.flatMap { start in
            source?.globalStartUTF16.map { start - $0 }
        }
        let localEnd = globalEnd.flatMap { end in
            source?.globalStartUTF16.map { end - $0 }
        }
        return AIDocumentChunk(
            id: "annotation:\(item.id.uuidString)",
            bookFingerprintKey: locator.bookFingerprint.canonicalKey,
            sourceUnitID: source?.sourceUnitID ?? "annotation:unresolved",
            sourceUnitIndex: source?.sourceUnitIndex,
            text: item.text,
            locator: locator,
            sourceLabel: source?.sourceLabel,
            chapterTitle: source?.chapterTitle,
            pageIndex: source?.pageIndex ?? locator.page,
            href: source?.href ?? locator.href,
            localStartUTF16: localStart,
            localEndUTF16: localEnd,
            globalStartUTF16: globalStart,
            globalEndUTF16: globalEnd,
            isOCRDerived: false
        )
    }
}
