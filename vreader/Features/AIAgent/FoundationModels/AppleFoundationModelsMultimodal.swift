// Purpose: Bounded multimodal document analysis support for Apple Foundation Models.
// Bounds render resolution and page counts to prevent memory bloat or context overflows.

import Foundation
import CoreGraphics

struct AppleMultimodalDocumentInput: Sendable {
    let bookFingerprintKey: String
    let pageIndex: Int
    let locator: Locator
    let maxDimension: CGFloat
    let userPrompt: String

    init(
        bookFingerprintKey: String,
        pageIndex: Int,
        locator: Locator,
        maxDimension: CGFloat = 1200.0,
        userPrompt: String
    ) {
        self.bookFingerprintKey = bookFingerprintKey
        self.pageIndex = pageIndex
        self.locator = locator
        self.maxDimension = max(600.0, min(maxDimension, 1800.0))
        self.userPrompt = userPrompt
    }
}

struct AppleFoundationModelsMultimodal: Sendable {
    /// Validates whether a multimodal request complies with bounded document policies.
    static func validate(input: AppleMultimodalDocumentInput) -> Bool {
        return input.pageIndex >= 0 &&
               input.maxDimension <= 1800.0 &&
               !input.userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
