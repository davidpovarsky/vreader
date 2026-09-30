// Purpose: Policies and language capabilities for on-device Vision OCR.
// Dynamically checks supported recognition languages and decides when OCR is required.

import Foundation

struct PDFOCRPolicy: Sendable {
    static let currentPipelineVersion = "vision-v1"

    /// Minimum non-whitespace characters to consider a page's native text layer valid.
    let nativeTextThreshold: Int
    /// Maximum image dimension for OCR rendering (to bound memory and compute).
    let maxRenderDimension: CGFloat

    init(nativeTextThreshold: Int = 25, maxRenderDimension: CGFloat = 1600.0) {
        self.nativeTextThreshold = max(5, nativeTextThreshold)
        self.maxRenderDimension = max(800.0, min(maxRenderDimension, 2400.0))
    }

    /// Evaluates if a page's native text is sufficient or if OCR should be attempted.
    func needsOCR(nativeText: String) -> Bool {
        let trimmed = nativeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count < nativeTextThreshold
    }

    /// Evaluates if a page's native text is sufficient or if OCR should be attempted (test alias).
    func requiresOCR(nativeText: String) -> Bool {
        needsOCR(nativeText: nativeText)
    }

    /// Returns preferred recognition languages, checking for Hebrew ("he-IL" or "he") support if available.
    func preferredLanguages(supportedLanguages: [String]) -> [String] {
        var languages: [String] = []
        if supportedLanguages.contains("he-IL") {
            languages.append("he-IL")
        } else if supportedLanguages.contains("he") {
            languages.append("he")
        }
        if supportedLanguages.contains("en-US") {
            languages.append("en-US")
        } else if supportedLanguages.contains("en") {
            languages.append("en")
        }
        return languages.isEmpty ? supportedLanguages : languages
    }
}
