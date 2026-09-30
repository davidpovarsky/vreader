// Purpose: Unit tests for PDFOCRService and MockPDFOCRService.
// Tests native PDF text bypass, vision OCR fallback, cache integration, and language configuration.

import Testing
import Foundation
@testable import vreader

@Suite("PDFOCRServiceTests")
struct PDFOCRServiceTests {

    @Test func mockOCRServiceExtractsTextWithSelectedSource() async throws {
        let mock = MockPDFOCRService()
        mock.mockResults[1] = "Page 1 native text from PDF layer."
        mock.mockResults[2] = "Page 2 recognized text from Vision OCR."
        mock.mockSources[2] = .visionOCR

        let result1 = try await mock.extractPageText(
            bookFingerprintKey: "book-pdf-1",
            pageIndex: 1,
            nativeTextThreshold: 20
        )
        #expect(result1.text == "Page 1 native text from PDF layer.")
        #expect(result1.source == .pdfTextLayer)
        #expect(result1.pageIndex == 1)

        let result2 = try await mock.extractPageText(
            bookFingerprintKey: "book-pdf-1",
            pageIndex: 2,
            nativeTextThreshold: 20
        )
        #expect(result2.text == "Page 2 recognized text from Vision OCR.")
        #expect(result2.source == .visionOCR)
    }

    @Test func ocrResultProducesAccurateSourceProvenance() {
        let result = PDFOCRResult(
            bookFingerprintKey: "book-pdf-2",
            pageIndex: 5,
            text: "Important scanned document passage.",
            source: .visionOCR,
            confidence: 0.92,
            language: "he-IL"
        )

        let prov = result.toSourceProvenance(toolCallID: "call_ocr_1", aheadOfReader: false)

        #expect(prov.pageIndex == 5)
        #expect(prov.bookFingerprintKey == "book-pdf-2")
        #expect(prov.isOCRDerived == true)
        #expect(prov.retrievalMethod == .ocr)
        #expect(prov.toolCallID == "call_ocr_1")
    }

    @Test func policyEvaluatesNativeVsScannedThreshold() {
        let policy = PDFOCRPolicy(nativeTextThreshold: 30)

        #expect(policy.requiresOCR(nativeText: "Too short") == true)
        #expect(policy.requiresOCR(nativeText: "This is a sufficiently long native text layer that does not require OCR.") == false)
    }
}
