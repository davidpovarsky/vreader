// Purpose: Data models for PDF text extraction and on-device Vision OCR.

import Foundation

enum PDFTextSource: String, Sendable, Codable, Equatable {
    case pdfTextLayer
    case visionOCR
}

struct PDFOCRResult: Sendable, Equatable, Codable {
    let bookFingerprintKey: String
    let pageIndex: Int
    let text: String
    let locator: Locator
    let source: PDFTextSource
    let isOCRDerived: Bool
    let confidence: Double?
    let languageCode: String?
    let timestamp: Date

    init(
        bookFingerprintKey: String,
        pageIndex: Int,
        text: String,
        locator: Locator? = nil,
        source: PDFTextSource = .visionOCR,
        isOCRDerived: Bool? = nil,
        confidence: Double? = nil,
        language: String? = nil,
        languageCode: String? = nil,
        timestamp: Date = Date()
    ) {
        self.bookFingerprintKey = bookFingerprintKey
        self.pageIndex = pageIndex
        self.text = text
        self.locator = locator ?? makePDFLocator(bookKey: bookFingerprintKey, pageIndex: pageIndex)
        self.source = source
        self.isOCRDerived = isOCRDerived ?? (source == .visionOCR)
        self.confidence = confidence
        self.languageCode = languageCode ?? language
        self.timestamp = timestamp
    }

    func toSourceProvenance(toolCallID: String? = nil, aheadOfReader: Bool = false) -> AISourceProvenance {
        AISourceProvenance(
            bookFingerprintKey: bookFingerprintKey,
            locator: locator,
            pageIndex: pageIndex,
            snippet: text,
            retrievalMethod: .ocr,
            score: confidence,
            aheadOfReader: aheadOfReader,
            toolCallID: toolCallID,
            isOCRDerived: isOCRDerived
        )
    }
}

enum PDFOCRError: Error, LocalizedError, Sendable {
    case pageOutOfBounds(page: Int, total: Int)
    case documentUnavailable
    case renderingFailed
    case ocrRecognitionFailed(String)
    case unsupportedLanguage(String)

    var errorDescription: String? {
        switch self {
        case .pageOutOfBounds(let page, let total):
            return "Requested page \(page + 1) is out of bounds (book has \(total) pages)."
        case .documentUnavailable:
            return "The PDF document is unavailable or locked."
        case .renderingFailed:
            return "Failed to render PDF page for OCR."
        case .ocrRecognitionFailed(let msg):
            return "Vision OCR text recognition failed: \(msg)"
        case .unsupportedLanguage(let lang):
            return "The requested recognition language (\(lang)) is not supported on this device."
        }
    }
}
