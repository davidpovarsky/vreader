// Purpose: PDF OCR extraction service utilizing native PDF text layer and Vision OCR fallback.
// Fully cached, spoiler-safe, cancellation-aware, and tested via mockable protocols.

import Foundation
import CryptoKit
#if canImport(Vision)
import Vision
#endif

protocol PDFOCRServicing: Sendable {
    func extractPageText(
        bookKey: String,
        pageIndex: Int,
        facade: any AIPDFDocumentFacading
    ) async throws -> PDFOCRResult
}

func makePDFLocator(bookKey: String, pageIndex: Int) -> Locator {
    let fp = DocumentFingerprint(canonicalKey: bookKey) ?? {
        let sha = SHA256.hash(data: Data(bookKey.utf8)).map { String(format: "%02x", $0) }.joined()
        return DocumentFingerprint(contentSHA256: sha, fileByteCount: 1024, format: .pdf)
    }()
    return Locator.validated(bookFingerprint: fp, page: pageIndex) ?? Locator(
        bookFingerprint: fp,
        href: nil,
        progression: nil,
        totalProgression: nil,
        cfi: nil,
        page: pageIndex,
        charOffsetUTF16: nil,
        charRangeStartUTF16: nil,
        charRangeEndUTF16: nil,
        textQuote: nil,
        textContextBefore: nil,
        textContextAfter: nil
    )
}

actor PDFOCRService: PDFOCRServicing {
    private let cache: PDFOCRCache
    private let policy: PDFOCRPolicy

    init(
        cache: PDFOCRCache = PDFOCRCache(),
        policy: PDFOCRPolicy = PDFOCRPolicy()
    ) {
        self.cache = cache
        self.policy = policy
    }

    func extractPageText(
        bookKey: String,
        pageIndex: Int,
        facade: any AIPDFDocumentFacading
    ) async throws -> PDFOCRResult {
        try Task.checkCancellation()

        // 1. Check Cache
        if let cached = await cache.get(bookKey: bookKey, pageIndex: pageIndex) {
            return cached
        }

        // 2. Check native PDF text layer
        let nativeText = try await facade.text(forPage: pageIndex)
        let locator = makePDFLocator(bookKey: bookKey, pageIndex: pageIndex)

        if !policy.needsOCR(nativeText: nativeText) {
            let result = PDFOCRResult(
                bookFingerprintKey: bookKey,
                pageIndex: pageIndex,
                text: nativeText,
                locator: locator,
                source: .pdfTextLayer,
                isOCRDerived: false
            )
            await cache.set(result)
            return result
        }

        // 3. Fallback to Vision OCR
        try Task.checkCancellation()
        let ocrText = try await performVisionOCR(pageIndex: pageIndex, facade: facade)
        try Task.checkCancellation()

        let chosenText = ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nativeText : ocrText
        guard !chosenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "vreader.ocr",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No text detected on page \(pageIndex + 1). Both native text and Vision OCR were empty."]
            )
        }

        let result = PDFOCRResult(
            bookFingerprintKey: bookKey,
            pageIndex: pageIndex,
            text: chosenText,
            locator: locator,
            source: ocrText.isEmpty ? .pdfTextLayer : .visionOCR,
            isOCRDerived: !ocrText.isEmpty
        )
        await cache.set(result)
        return result
    }

    private func performVisionOCR(pageIndex: Int, facade: any AIPDFDocumentFacading) async throws -> String {
        try Task.checkCancellation()
        guard let image = try await facade.renderPageForOCR(index: pageIndex, maxDimension: 1800) else {
            return ""
        }
        #if canImport(Vision)
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: recognizedStrings.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            // Runtime language detection: Hebrew & English
            if let supported = try? VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: VNRecognizeTextRequestRevision3) {
                var langs: [String] = []
                if supported.contains("he-IL") || supported.contains("he") {
                    langs.append("he")
                }
                langs.append(contentsOf: ["en-US", "en"])
                request.recognitionLanguages = langs
            }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
        #else
        return ""
        #endif
    }
}

/// Test/mock implementation of PDFOCRServicing for deterministic testing.
final class MockPDFOCRService: PDFOCRServicing, @unchecked Sendable {
    var mockResults: [Int: String] = [:]
    var mockSources: [Int: PDFTextSource] = [:]
    let mockOCRText: String?
    let policy: PDFOCRPolicy

    init(mockOCRText: String? = nil, policy: PDFOCRPolicy = PDFOCRPolicy()) {
        self.mockOCRText = mockOCRText
        self.policy = policy
    }

    func extractPageText(
        bookKey: String,
        pageIndex: Int,
        facade: any AIPDFDocumentFacading
    ) async throws -> PDFOCRResult {
        try Task.checkCancellation()
        let text = mockResults[pageIndex] ?? (pageIndex == 0 ? mockResults[1] : nil)
        let source = mockSources[pageIndex] ?? (pageIndex == 0 ? mockSources[1] : nil)
        if let text {
            let actualSource = source ?? (policy.needsOCR(nativeText: text) ? .visionOCR : .pdfTextLayer)
            return PDFOCRResult(
                bookFingerprintKey: bookKey,
                pageIndex: pageIndex,
                text: text,
                locator: makePDFLocator(bookKey: bookKey, pageIndex: pageIndex),
                source: actualSource,
                isOCRDerived: actualSource == .visionOCR
            )
        }
        let nativeText = try await facade.text(forPage: pageIndex)
        let locator = makePDFLocator(bookKey: bookKey, pageIndex: pageIndex)

        if !policy.needsOCR(nativeText: nativeText) {
            return PDFOCRResult(
                bookFingerprintKey: bookKey,
                pageIndex: pageIndex,
                text: nativeText,
                locator: locator,
                source: .pdfTextLayer,
                isOCRDerived: false
            )
        }

        let ocrText = mockOCRText ?? "Simulated Vision OCR text for page \(pageIndex + 1)"
        return PDFOCRResult(
            bookFingerprintKey: bookKey,
            pageIndex: pageIndex,
            text: ocrText,
            locator: locator,
            source: .visionOCR,
            isOCRDerived: true
        )
    }

    func extractPageText(
        bookFingerprintKey: String,
        pageIndex: Int,
        nativeTextThreshold: Int = 20
    ) async throws -> PDFOCRResult {
        let text = mockResults[pageIndex] ?? (pageIndex == 0 ? mockResults[1] : nil) ?? mockOCRText ?? ""
        let source = mockSources[pageIndex] ?? (pageIndex == 0 ? mockSources[1] : nil) ?? (text.count < nativeTextThreshold ? .visionOCR : .pdfTextLayer)
        return PDFOCRResult(
            bookFingerprintKey: bookFingerprintKey,
            pageIndex: pageIndex,
            text: text,
            locator: makePDFLocator(bookKey: bookFingerprintKey, pageIndex: pageIndex),
            source: source,
            isOCRDerived: source == .visionOCR
        )
    }
}
