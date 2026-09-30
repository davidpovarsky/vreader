// Purpose: Unit tests for ExtractPageTextTool (extract_page_text).
// Validates page parameter parsing, readCurrentBook permission gating, spoiler boundary checks, and OCR extraction.

import Testing
import Foundation
@testable import vreader

@MainActor
private final class MockReaderToolContext: AIReaderToolContextProviding {
    let bookTitle: String
    let fingerprint: DocumentFingerprint
    let sessionID: AIDocumentSessionID
    var stubbedDocument: AILiveReaderDocument?

    init(
        bookTitle: String = "Test PDF",
        fingerprint: DocumentFingerprint = DocumentFingerprint(scheme: "test", value: "pdf-doc-1"),
        stubbedDocument: AILiveReaderDocument? = nil
    ) {
        self.bookTitle = bookTitle
        self.fingerprint = fingerprint
        self.sessionID = AIDocumentSessionID(fingerprintKey: fingerprint.canonicalKey, readerToken: UUID())
        self.stubbedDocument = stubbedDocument
    }

    func resolveDocument() async -> AILiveReaderDocument? {
        stubbedDocument
    }

    func tableOfContents() async -> [AIDocumentTOCSummaryItem] {
        []
    }
}

@Suite("AIExtractPageTextToolTests")
struct AIExtractPageTextToolTests {

    @Test @MainActor func toolRejectsMissingOrInvalidPageParameter() async {
        let mockOCR = MockPDFOCRService()
        let context = MockReaderToolContext()
        let gate = AIAgentToolExecutionGate.productionUnavailable()
        let tool = ExtractPageTextTool(ocrService: mockOCR, context: context, authorizationGate: gate)

        // Missing page
        let res1 = await tool.run(.object([:]))
        #expect(res1.isError)
        #expect(res1.content.contains("positive integer"))

        // Negative page
        let res2 = await tool.run(.object(["page": .number(-1)]))
        #expect(res2.isError)
    }

    @Test @MainActor func toolExtractsTextForValidPageWithinAllowedBoundary() async {
        let mockOCR = MockPDFOCRService()
        mockOCR.mockResults[1] = "Extracted text of page 1."

        let locator = Locator(href: "page_1.pdf", type: "application/pdf", title: "Page 1")
        let docChunk = AIDocumentChunk(
            unit: .page(number: 1),
            locator: locator,
            text: "Page 1",
            isSafeCurrentSection: true,
            isSafeBookSoFar: true,
            isAheadOfReader: false
        )
        let snapshot = AIDocumentSnapshot(
            bookFingerprint: DocumentFingerprint(scheme: "test", value: "pdf-doc-1"),
            format: .pdf,
            chunks: [docChunk]
        )
        let liveDoc = AILiveReaderDocument(snapshot: snapshot, chunks: [docChunk])
        let context = MockReaderToolContext(stubbedDocument: liveDoc)

        let store = InMemoryAIAgentPreferencesStore()
        store.preferences.permissions[.readCurrentBook] = .allow
        let gate = AIAgentToolExecutionGate(
            preferencesStore: store,
            broker: AIActionConfirmationBroker(preferencesStore: store),
            confirmationAvailability: .brokerConnected
        )

        let tool = ExtractPageTextTool(ocrService: mockOCR, context: context, authorizationGate: gate)

        let res = await tool.run(.object(["page": .number(1)]))
        #expect(!res.isError)
        #expect(res.content.contains("Extracted text of page 1."))
    }
}
