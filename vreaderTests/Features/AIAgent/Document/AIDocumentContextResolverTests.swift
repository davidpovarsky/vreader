// Purpose: Feature #177 WI-4 RED contracts for structured reader-AI scopes.

import Foundation
import Testing
#if canImport(vreader)
@testable import vreader
#endif

@Suite("Feature #177 WI-4 — structured context resolver")
struct AIDocumentContextResolverTests {
    private let resolver = AIDocumentContextResolver()

    @Test("PDF Section uses the exact current page, not a flattened prefix")
    func pdfSectionUsesPage50() {
        let fp = fingerprint("1", .pdf)
        let pages = (0...50).map { chunk(fp, id: "pdf:page:\($0)", index: $0, text: "page \($0)", page: $0) }
        let snapshot = makeSnapshot(fp, format: .pdf, current: pages[50], boundaryLocal: pages[50].text.utf16.count)

        let result = resolver.resolve(snapshot: snapshot, orderedChunks: pages, scope: .section, maxUTF16: 12_000)

        #expect(result.text == "page 50")
        #expect(result.sourceUnitIDs == ["pdf:page:50"])
        #expect(!result.text.contains("page 0"))
    }

    @Test("EPUB Section and Chapter use exact href B despite identical text and contradictory totalProgression")
    func epubUsesExactHref() {
        let fp = fingerprint("2", .epub)
        let a = chunk(fp, id: "epub:a.xhtml", index: 0, text: "same", href: "a.xhtml", total: 0.99)
        let b = chunk(fp, id: "epub:b.xhtml", index: 1, text: "same", href: "b.xhtml", total: 0.01)
        let snapshot = makeSnapshot(fp, format: .epub, current: b, boundaryLocal: nil)

        for scope in [AIDocumentContextScope.section, .chapter] {
            let result = resolver.resolve(snapshot: snapshot, orderedChunks: [a, b], scope: scope, maxUTF16: 12_000)
            #expect(result.sourceUnitIDs == ["epub:b.xhtml"])
            #expect(result.currentLocator.href == "b.xhtml")
        }
    }

    @Test("TXT Book-so-far cuts at an exact surrogate-safe UTF-16 boundary")
    func txtBookSoFarExactEmojiBoundary() {
        let fp = fingerprint("3", .txt)
        let text = "AA😀BB"
        let unit = chunk(fp, id: "txt:segment:0", index: 0, text: text, globalStart: 0)
        let boundary = ("AA😀" as NSString).length
        let snapshot = makeSnapshot(fp, format: .txt, current: unit, boundaryLocal: boundary, boundaryGlobal: boundary)

        let result = resolver.resolve(snapshot: snapshot, orderedChunks: [unit], scope: .bookSoFar, maxUTF16: 12_000)

        #expect(result.text == "AA😀")
        #expect(!result.text.contains("BB"))
        #expect(result.text.utf16.count == boundary)
    }

    @Test("Markdown Chapter uses provider rendered-text bounds, never raw source offsets")
    func markdownUsesRenderedChapterBounds() {
        let fp = fingerprint("4", .md)
        let rendered = "Title\nRendered first\nNext\nRendered second"
        let unit = chunk(fp, id: "md:segment:0", index: 0, text: rendered, globalStart: 0)
        let start = (rendered as NSString).range(of: "Next").location
        let bounds = ChapterBounds(startUTF16: start, endUTF16: (rendered as NSString).length)
        let snapshot = makeSnapshot(fp, format: .md, current: unit, boundaryLocal: start, boundaryGlobal: start, chapterBounds: bounds)

        let result = resolver.resolve(snapshot: snapshot, orderedChunks: [unit], scope: .chapter, maxUTF16: 12_000)

        #expect(result.text == "Next\nRendered second")
        #expect(!result.text.contains("Rendered first"))
    }

    @Test("PDF Book-so-far excludes all later pages")
    func pdfBookSoFarDoesNotReadAhead() {
        let fp = fingerprint("5", .pdf)
        let pages = (0...3).map { chunk(fp, id: "pdf:page:\($0)", index: $0, text: "P\($0)", page: $0) }
        let snapshot = makeSnapshot(fp, format: .pdf, current: pages[1], boundaryLocal: pages[1].text.utf16.count)

        let result = resolver.resolve(snapshot: snapshot, orderedChunks: pages, scope: .bookSoFar, maxUTF16: 12_000)

        #expect(result.text.contains("P0"))
        #expect(result.text.contains("P1"))
        #expect(!result.text.contains("P2"))
        #expect(!result.text.contains("P3"))
    }

    @Test("EPUB Book-so-far keeps prior resources but fails closed on current unread suffix")
    func epubBookSoFarOmitsCurrentAndLater() {
        let fp = fingerprint("6", .epub)
        let a = chunk(fp, id: "epub:a", index: 0, text: "PRIOR", href: "a")
        let b = chunk(fp, id: "epub:b", index: 1, text: "CURRENT SECRET", href: "b")
        let c = chunk(fp, id: "epub:c", index: 2, text: "LATER", href: "c")
        let snapshot = makeSnapshot(fp, format: .epub, current: b, boundaryLocal: nil)

        let result = resolver.resolve(snapshot: snapshot, orderedChunks: [a, b, c], scope: .bookSoFar, maxUTF16: 12_000)

        #expect(result.text == "PRIOR")
        #expect(result.sourceUnitIDs == ["epub:a"])
        #expect(!result.text.contains("SECRET"))
        #expect(!result.text.contains("LATER"))
    }

    @Test("Unknown source ordering fails closed even when totalProgression looks earlier")
    func unknownOrderingFailsClosed() {
        let fp = fingerprint("7", .epub)
        let current = chunk(fp, id: "epub:current", index: nil, text: "CURRENT", href: "current", total: 0.8)
        let unknown = chunk(fp, id: "epub:unknown", index: nil, text: "UNKNOWN", href: "unknown", total: 0.1)
        let snapshot = makeSnapshot(fp, format: .epub, current: current, boundaryLocal: nil)

        let result = resolver.resolve(snapshot: snapshot, orderedChunks: [unknown, current], scope: .bookSoFar, maxUTF16: 12_000)

        #expect(result.text.isEmpty)
        #expect(result.sourceUnitIDs.isEmpty)
        #expect(result.coverage.droppedSourceUnitIDs.contains("epub:unknown"))
    }

    private func fingerprint(_ digit: Character, _ format: BookFormat) -> DocumentFingerprint {
        DocumentFingerprint(contentSHA256: String(repeating: digit, count: 64), fileByteCount: 100, format: format)
    }

    private func chunk(
        _ fp: DocumentFingerprint,
        id: String,
        index: Int?,
        text: String,
        page: Int? = nil,
        href: String? = nil,
        total: Double? = nil,
        globalStart: Int? = nil
    ) -> AIDocumentChunk {
        let locator = Locator.validated(bookFingerprint: fp, href: href, totalProgression: total, page: page, charOffsetUTF16: globalStart)!
        return AIDocumentChunk(
            id: "\(fp.canonicalKey):\(id)", bookFingerprintKey: fp.canonicalKey,
            sourceUnitID: id, sourceUnitIndex: index, text: text, locator: locator,
            sourceLabel: nil, chapterTitle: nil, pageIndex: page, href: href,
            localStartUTF16: 0, localEndUTF16: text.utf16.count,
            globalStartUTF16: globalStart,
            globalEndUTF16: globalStart.map { $0 + text.utf16.count },
            isOCRDerived: false
        )
    }

    private func makeSnapshot(
        _ fp: DocumentFingerprint,
        format: BookFormat,
        current: AIDocumentChunk,
        boundaryLocal: Int?,
        boundaryGlobal: Int? = nil,
        chapterBounds: ChapterBounds? = nil
    ) -> AIDocumentSnapshot {
        AIDocumentSnapshot(
            bookFingerprint: fp, format: format, currentLocator: current.locator,
            currentSourceUnitID: current.sourceUnitID, currentSectionChunks: [current],
            visibleChunks: [current], currentChapterLabel: current.chapterTitle,
            currentChapterBounds: chapterBounds, tocSummary: [],
            readSoFarBoundary: AIReadSoFarBoundary(
                locator: current.locator, sourceUnitID: current.sourceUnitID,
                sourceUnitIndex: current.sourceUnitIndex,
                localOffsetUTF16: boundaryLocal, globalOffsetUTF16: boundaryGlobal
            ), exactMappingAvailable: true
        )
    }
}
