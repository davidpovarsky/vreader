// Purpose: Feature #177 WI-3 RED contracts for exact PDF and Readium mapping.

import Foundation
import Testing

@Suite("Feature #177 WI-3 — PDF and Readium resource mapping")
@MainActor
struct AIPagedAndResourceDocumentProviderTests {
    private let pdfFingerprint = DocumentFingerprint(
        contentSHA256: String(repeating: "3", count: 64),
        fileByteCount: 300,
        format: .pdf
    )
    private let epubFingerprint = DocumentFingerprint(
        contentSHA256: String(repeating: "4", count: 64),
        fileByteCount: 400,
        format: .epub
    )

    @Test("PDF page 50 remains page 50 and never becomes flattened prefix text")
    func pdfPage50IsExact() async throws {
        let pages = (0...50).map { "native page \($0)" }
        let facade = PDFValueFacade(pages: pages, currentPageIndex: 50)
        let provider = AIPDFDocumentProvider(
            fingerprint: pdfFingerprint,
            facade: facade
        )

        let snapshot = try await provider.snapshot()

        #expect(snapshot.currentSourceUnitID == "pdf:page:50")
        #expect(snapshot.currentLocator?.page == 50)
        #expect(snapshot.currentSectionChunks.map(\.text) == ["native page 50"])
        #expect(snapshot.currentSectionChunks.first?.pageIndex == 50)
        #expect(snapshot.currentSectionChunks.first?.locator.page == 50)
    }

    @Test("empty PDF page preserves every later zero-based page index")
    func emptyPDFPagePreservesAlignment() async throws {
        let facade = PDFValueFacade(
            pages: ["page zero", "", "page two"],
            currentPageIndex: 2
        )
        let provider = AIPDFDocumentProvider(
            fingerprint: pdfFingerprint,
            facade: facade
        )

        let chunks = try await provider.chunks()

        #expect(chunks.map(\.sourceUnitID) == ["pdf:page:0", "pdf:page:1", "pdf:page:2"])
        #expect(chunks[1].text.isEmpty)
        #expect(chunks[2].locator.page == 2)
        #expect(chunks.allSatisfy { $0.bookFingerprintKey == pdfFingerprint.canonicalKey })
    }

    @Test("identical EPUB text remains distinct by exact href")
    func identicalEPUBTextRemainsDistinct() async throws {
        let facade = ReadiumValueFacade(
            resources: [
                resource(index: 0, href: "OEBPS/a.xhtml", text: "same text"),
                resource(index: 1, href: "OEBPS/b.xhtml", text: "same text"),
            ],
            currentLocator: epubLocator(href: "OEBPS/b.xhtml", progression: 0.25, total: 0.01)
        )
        let provider = AIReadiumDocumentProvider(
            fingerprint: epubFingerprint,
            facade: facade
        )

        let chunks = try await provider.chunks()

        #expect(chunks.map(\.sourceUnitID) == ["epub:OEBPS/a.xhtml", "epub:OEBPS/b.xhtml"])
        #expect(chunks.map(\.href) == ["OEBPS/a.xhtml", "OEBPS/b.xhtml"])
        #expect(chunks[0].text == chunks[1].text)
        #expect(chunks[0].id != chunks[1].id)
    }

    @Test("EPUB current resource resolves by href, never contradictory totalProgression")
    func currentEPUBUsesHref() async throws {
        let facade = ReadiumValueFacade(
            resources: [
                resource(index: 0, href: "OPS/first.xhtml", text: "first"),
                resource(index: 1, href: "OPS/last.xhtml", text: "last"),
            ],
            currentLocator: epubLocator(href: "OPS/last.xhtml", progression: 0.4, total: 0.0)
        )
        let provider = AIReadiumDocumentProvider(
            fingerprint: epubFingerprint,
            facade: facade
        )

        let snapshot = try await provider.snapshot()

        #expect(snapshot.currentSourceUnitID == "epub:OPS/last.xhtml")
        #expect(snapshot.currentSectionChunks.map(\.text) == ["last"])
        #expect(snapshot.readSoFarBoundary.sourceUnitIndex == 1)
        #expect(snapshot.currentLocator?.href == "OPS/last.xhtml")
    }

    @Test("Readium href normalization matches a unique navigation-safe resource")
    func hrefNormalization() async throws {
        let facade = ReadiumValueFacade(
            resources: [
                resource(index: 0, href: "OEBPS/Text/chapter.xhtml", text: "chapter"),
                resource(index: 1, href: "OEBPS/Text/next.xhtml", text: "next"),
            ],
            currentLocator: epubLocator(href: "Text/chapter.xhtml", progression: 0.5, total: 0.5)
        )
        let provider = AIReadiumDocumentProvider(
            fingerprint: epubFingerprint,
            facade: facade
        )

        let snapshot = try await provider.snapshot()

        #expect(snapshot.currentSourceUnitID == "epub:OEBPS/Text/chapter.xhtml")
        #expect(snapshot.currentLocator?.href == "OEBPS/Text/chapter.xhtml")
    }

    @Test("inaccessible EPUB resource yields partial safe output without href corruption")
    func inaccessibleEPUBResourceIsPartial() async throws {
        let facade = ReadiumValueFacade(
            resources: [
                resource(index: 0, href: "a.xhtml", text: "available"),
                resource(index: 1, href: "locked.xhtml", text: nil),
                resource(index: 2, href: "empty.xhtml", text: ""),
            ],
            currentLocator: epubLocator(href: "a.xhtml", progression: 0.1, total: 0.1)
        )
        let provider = AIReadiumDocumentProvider(
            fingerprint: epubFingerprint,
            facade: facade
        )

        let chunks = try await provider.chunks()

        #expect(chunks.map(\.sourceUnitID) == ["epub:a.xhtml", "epub:empty.xhtml"])
        #expect(chunks[1].text.isEmpty)
        #expect(chunks.allSatisfy { $0.bookFingerprintKey == epubFingerprint.canonicalKey })
    }

    private func resource(index: Int, href: String, text: String?) -> AIReadiumResource {
        AIReadiumResource(
            href: href,
            sourceUnitIndex: index,
            title: nil,
            text: text,
            locator: epubLocator(href: href, progression: 0, total: nil)
        )
    }

    private func epubLocator(href: String, progression: Double?, total: Double?) -> Locator {
        Locator.validated(
            bookFingerprint: epubFingerprint,
            href: href,
            progression: progression,
            totalProgression: total
        )!
    }
}

@MainActor
private final class PDFValueFacade: AIPDFDocumentFacading {
    let pages: [String]
    var currentPageIndex: Int?
    var pageCount: Int { pages.count }

    init(pages: [String], currentPageIndex: Int?) {
        self.pages = pages
        self.currentPageIndex = currentPageIndex
    }

    func text(forPage index: Int) async throws -> String {
        pages[index]
    }
}

@MainActor
private final class ReadiumValueFacade: AIReadiumPublicationFacading {
    let storedResources: [AIReadiumResource]
    var currentLocator: Locator?

    init(resources: [AIReadiumResource], currentLocator: Locator?) {
        storedResources = resources
        self.currentLocator = currentLocator
    }

    func resources() async throws -> [AIReadiumResource] {
        storedResources
    }
}
