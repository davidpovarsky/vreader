// Purpose: Tests for AIRequest.cacheKey — verifies that semantic fields
// (userPrompt, targetLanguage, contextText) are included in the cache key.

import Testing
import Foundation
@testable import vreader

@Suite("AIRequest.cacheKey")
struct AIRequestCacheKeyTests {

    // MARK: - Helpers

    private static let testFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 1024,
        format: .txt
    )

    private static func makeLocator() -> Locator {
        Locator(
            bookFingerprint: testFP,
            href: nil, progression: nil, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: 0,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    // MARK: - Issue 2: Semantic fields in cache key

    @Test func differentUserPromptsProduceDifferentKeys() {
        let r1 = AIRequest(
            actionType: .questionAnswer,
            bookFingerprint: Self.testFP,
            locator: Self.makeLocator(),
            contextText: "same context",
            userPrompt: "What is this?",
            targetLanguage: nil,
            promptVersion: "v1"
        )
        let r2 = AIRequest(
            actionType: .questionAnswer,
            bookFingerprint: Self.testFP,
            locator: Self.makeLocator(),
            contextText: "same context",
            userPrompt: "Why is this?",
            targetLanguage: nil,
            promptVersion: "v1"
        )
        #expect(r1.cacheKey != r2.cacheKey)
    }

    @Test func differentTargetLanguagesProduceDifferentKeys() {
        let r1 = AIRequest(
            actionType: .translate,
            bookFingerprint: Self.testFP,
            locator: Self.makeLocator(),
            contextText: "Hello world",
            userPrompt: nil,
            targetLanguage: "Chinese",
            promptVersion: "v1"
        )
        let r2 = AIRequest(
            actionType: .translate,
            bookFingerprint: Self.testFP,
            locator: Self.makeLocator(),
            contextText: "Hello world",
            userPrompt: nil,
            targetLanguage: "Japanese",
            promptVersion: "v1"
        )
        #expect(r1.cacheKey != r2.cacheKey)
    }

    @Test func sameInputsProduceSameKey() {
        let r1 = AIRequest(
            actionType: .summarize,
            bookFingerprint: Self.testFP,
            locator: Self.makeLocator(),
            contextText: "Some text",
            userPrompt: nil,
            targetLanguage: nil,
            promptVersion: "v1"
        )
        let r2 = AIRequest(
            actionType: .summarize,
            bookFingerprint: Self.testFP,
            locator: Self.makeLocator(),
            contextText: "Some text",
            userPrompt: nil,
            targetLanguage: nil,
            promptVersion: "v1"
        )
        #expect(r1.cacheKey == r2.cacheKey)
    }

    @Test func differentContextTextsProduceDifferentKeys() {
        let r1 = AIRequest(
            actionType: .summarize,
            bookFingerprint: Self.testFP,
            locator: Self.makeLocator(),
            contextText: "First passage",
            userPrompt: nil,
            targetLanguage: nil,
            promptVersion: "v1"
        )
        let r2 = AIRequest(
            actionType: .summarize,
            bookFingerprint: Self.testFP,
            locator: Self.makeLocator(),
            contextText: "Second passage",
            userPrompt: nil,
            targetLanguage: nil,
            promptVersion: "v1"
        )
        #expect(r1.cacheKey != r2.cacheKey)
    }

    // MARK: - Issue 3: Optional fingerprint

    @Test func nilFingerprintUsesGeneralPrefix() {
        let r1 = AIRequest(
            actionType: .questionAnswer,
            bookFingerprint: nil,
            locator: nil,
            contextText: "general question context",
            userPrompt: "What is AI?",
            targetLanguage: nil,
            promptVersion: "v1"
        )
        #expect(r1.cacheKey.hasPrefix("general:"))
    }

    @Test func nilVsNonNilFingerprintProduceDifferentKeys() {
        let withFP = AIRequest(
            actionType: .summarize,
            bookFingerprint: Self.testFP,
            locator: Self.makeLocator(),
            contextText: "text",
            userPrompt: nil,
            targetLanguage: nil,
            promptVersion: "v1"
        )
        let withoutFP = AIRequest(
            actionType: .summarize,
            bookFingerprint: nil,
            locator: nil,
            contextText: "text",
            userPrompt: nil,
            targetLanguage: nil,
            promptVersion: "v1"
        )
        #expect(withFP.cacheKey != withoutFP.cacheKey)
    }

    @Test func nilUserPromptAndEmptyUserPromptProduceSameKey() {
        let r1 = AIRequest(
            actionType: .summarize,
            bookFingerprint: Self.testFP,
            locator: Self.makeLocator(),
            contextText: "text",
            userPrompt: nil,
            targetLanguage: nil,
            promptVersion: "v1"
        )
        let r2 = AIRequest(
            actionType: .summarize,
            bookFingerprint: Self.testFP,
            locator: Self.makeLocator(),
            contextText: "text",
            userPrompt: nil,
            targetLanguage: nil,
            promptVersion: "v1"
        )
        #expect(r1.cacheKey == r2.cacheKey)
    }
}
