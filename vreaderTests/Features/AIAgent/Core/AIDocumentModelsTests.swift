// Purpose: Feature #177 WI-2 RED contract for structured document context.
// These types replace flattened text as the source of location/provenance truth.
//
// @coordinates-with: vreader/Features/AIAgent/Core/AIDocumentModels.swift

import Foundation
import Testing
#if !FEATURE_177_CORE_TESTS
@testable import vreader
#endif

@Suite("Feature #177 — structured AI document models")
struct AIDocumentModelsTests {
    private let fingerprint = DocumentFingerprint.validated(
        contentSHA256: String(repeating: "a", count: 64),
        fileByteCount: 4_096,
        format: .pdf
    )!

    private func locator(page: Int = 49) -> Locator {
        Locator.validated(bookFingerprint: fingerprint, page: page)!
    }

    @Test("a chunk retains exact PDF page and source-unit identity")
    func chunkRetainsExactPageIdentity() throws {
        let chunk = AIDocumentChunk(
            id: "pdf:page:49:0",
            bookFingerprintKey: fingerprint.canonicalKey,
            sourceUnitID: "pdf-page-49",
            sourceUnitIndex: 49,
            text: "עמוד חמישים",
            locator: locator(),
            sourceLabel: "Page 50",
            chapterTitle: nil,
            pageIndex: 49,
            href: nil,
            localStartUTF16: 0,
            localEndUTF16: 11,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )

        #expect(chunk.id == "pdf:page:49:0")
        #expect(chunk.sourceUnitID == "pdf-page-49")
        #expect(chunk.pageIndex == 49)
        #expect(chunk.locator.page == 49)
        #expect(chunk.href == nil)

        let decoded = try JSONDecoder().decode(
            AIDocumentChunk.self,
            from: JSONEncoder().encode(chunk)
        )
        #expect(decoded == chunk)
    }

    @Test("source provenance keeps navigation, ranking, and tool identity")
    func provenanceRetainsNavigationAndToolIdentity() throws {
        let provenance = AISourceProvenance(
            id: "source-1",
            bookFingerprintKey: fingerprint.canonicalKey,
            bookTitle: "ספר בדיקה",
            locator: locator(page: 7),
            sourceLabel: "Page 8",
            chapterTitle: nil,
            pageIndex: 7,
            snippet: "קטע שנמצא בחיפוש סמנטי",
            retrievalMethod: .semanticSearch,
            score: 0.83,
            rank: 2,
            aheadOfReader: true,
            toolCallID: "tool-42",
            mcpServerName: nil
        )

        #expect(provenance.locator.page == 7)
        #expect(provenance.retrievalMethod == .semanticSearch)
        #expect(provenance.aheadOfReader)
        #expect(provenance.toolCallID == "tool-42")
        #expect(provenance.rank == 2)

        let decoded = try JSONDecoder().decode(
            AISourceProvenance.self,
            from: JSONEncoder().encode(provenance)
        )
        #expect(decoded == provenance)
    }

    @Test("provenance snippets are bounded without splitting grapheme clusters")
    func provenanceSnippetIsBounded() {
        let long = String(repeating: "👨‍👩‍👧‍👦", count: 700)
        let provenance = AISourceProvenance(
            id: "source-long",
            bookFingerprintKey: fingerprint.canonicalKey,
            bookTitle: "Long",
            locator: locator(),
            sourceLabel: nil,
            chapterTitle: nil,
            pageIndex: 49,
            snippet: long,
            retrievalMethod: .currentContext,
            score: nil,
            rank: nil,
            aheadOfReader: false,
            toolCallID: nil,
            mcpServerName: nil
        )

        #expect(provenance.snippet.count == AISourceProvenance.maximumSnippetCharacters)
        #expect(provenance.snippet.last == "👨‍👩‍👧‍👦")
    }

    @Test("snapshot carries exact current source and read-so-far boundary")
    func snapshotCarriesStructuredReaderState() {
        let current = AIDocumentChunk(
            id: "pdf:page:49:0",
            bookFingerprintKey: fingerprint.canonicalKey,
            sourceUnitID: "pdf-page-49",
            sourceUnitIndex: 49,
            text: "current",
            locator: locator(),
            sourceLabel: "Page 50",
            chapterTitle: nil,
            pageIndex: 49,
            href: nil,
            localStartUTF16: 0,
            localEndUTF16: 7,
            globalStartUTF16: nil,
            globalEndUTF16: nil,
            isOCRDerived: false
        )
        let boundary = AIReadSoFarBoundary(
            locator: locator(),
            sourceUnitID: "pdf-page-49",
            sourceUnitIndex: 49,
            localOffsetUTF16: 7
        )
        let snapshot = AIDocumentSnapshot(
            bookFingerprint: fingerprint,
            format: .pdf,
            currentLocator: locator(),
            currentSourceUnitID: "pdf-page-49",
            currentSectionChunks: [current],
            visibleChunks: [current],
            currentChapterLabel: nil,
            currentChapterBounds: nil,
            tocSummary: [
                AIDocumentTOCSummaryItem(
                    id: "page-49",
                    title: "Page 50",
                    depth: 0,
                    locator: locator()
                ),
            ],
            readSoFarBoundary: boundary,
            exactMappingAvailable: true
        )

        #expect(snapshot.currentSourceUnitID == "pdf-page-49")
        #expect(snapshot.currentSectionChunks == [current])
        #expect(snapshot.readSoFarBoundary.sourceUnitIndex == 49)
        #expect(snapshot.exactMappingAvailable)
    }

    @Test("reading-ahead policy has the three required persisted modes")
    func readingPolicyModesAreStable() throws {
        let modes: [AIReadAheadMode] = [
            .neverReadAhead,
            .askBeforeReadingAhead,
            .wholeBookAllowed,
        ]
        let data = try JSONEncoder().encode(modes)
        #expect(try JSONDecoder().decode([AIReadAheadMode].self, from: data) == modes)
        #expect(modes.map(\.rawValue) == ["never", "ask", "wholeBook"])
    }

    @Test("all required provenance methods have stable wire values")
    func retrievalMethodWireValues() {
        #expect(AISourceRetrievalMethod.allCases.map(\.rawValue) == [
            "currentContext",
            "lexicalSearch",
            "semanticSearch",
            "annotation",
            "ocr",
            "wholeBookDigest",
            "mcpExternal",
        ])
    }
}
