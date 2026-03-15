// Purpose: Tests for AITranslationViewModel — translation state management,
// bilingual view model, language picker, caching, and edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("AITranslationViewModel")
struct AITranslationViewModelTests {

    // MARK: - Helpers

    @MainActor
    private func makeViewModel(
        featureEnabled: Bool = true,
        hasConsent: Bool = true,
        provider: StubAIProvider? = nil
    ) -> (AITranslationViewModel, StubAIProvider) {
        let flags = FeatureFlags(environment: .prod)
        if featureEnabled {
            flags.setOverride(true, for: .aiAssistant)
        }

        let stub = provider ?? StubAIProvider()
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: hasConsent),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )

        let vm = AITranslationViewModel(aiService: service)
        return (vm, stub)
    }

    // MARK: - Initial State

    @Test @MainActor func initialStateIsIdle() {
        let (vm, _) = makeViewModel()
        #expect(vm.originalText.isEmpty)
        #expect(vm.translatedText == nil)
        #expect(vm.targetLanguage == "Chinese")
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.supportedLanguages.count >= 9)
    }

    // MARK: - Translate calls AI with target language

    @Test @MainActor func translateCallsAIWithTargetLanguage() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "这是翻译结果",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.translate(
            originalText: "This is the original text.",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt
        )

        #expect(stub.sendRequestCallCount == 1)
        #expect(stub.lastRequest?.actionType == .translate)
        #expect(stub.lastRequest?.targetLanguage == "Chinese")
    }

    // MARK: - Bilingual view model shows both texts

    @Test @MainActor func bilingualViewModelShowsBothTexts() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "翻译后的文本",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.translate(
            originalText: "Original text for translation.",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt
        )

        #expect(vm.originalText == "Original text for translation.")
        #expect(vm.translatedText == "翻译后的文本")
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Language picker sets target

    @Test @MainActor func languagePickerSetsTarget() {
        let (vm, _) = makeViewModel()

        vm.targetLanguage = "Japanese"
        #expect(vm.targetLanguage == "Japanese")

        vm.targetLanguage = "Spanish"
        #expect(vm.targetLanguage == "Spanish")
    }

    // MARK: - Translation cached for same content

    @Test @MainActor func translationCachedForSameContent() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Cached translation",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)
        let locator = WI11TestHelpers.makeLocator()

        // First call — hits provider
        await vm.translate(
            originalText: "Some text to translate.",
            locator: locator,
            format: .txt
        )
        #expect(stub.sendRequestCallCount == 1)
        #expect(vm.translatedText == "Cached translation")

        // Reset translated text to prove it's refetched from cache, not leftover
        vm.translatedText = nil
        vm.originalText = ""

        // Second call with same content + language — should use cache
        await vm.translate(
            originalText: "Some text to translate.",
            locator: locator,
            format: .txt
        )
        #expect(stub.sendRequestCallCount == 1, "Provider should not be called on cache hit")
        #expect(vm.translatedText == "Cached translation")
    }

    // MARK: - Different language produces different result

    @Test @MainActor func differentLanguageProducesDifferentResult() async {
        let stub = StubAIProvider()
        var callCount = 0
        stub.stubbedResponse = AIResponse(
            content: "Chinese translation",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)
        let locator = WI11TestHelpers.makeLocator()

        // Translate to Chinese
        vm.targetLanguage = "Chinese"
        await vm.translate(
            originalText: "Hello world",
            locator: locator,
            format: .txt
        )
        #expect(stub.sendRequestCallCount == 1)

        // Change to Japanese — different cache key, should call provider again
        vm.targetLanguage = "Japanese"
        stub.stubbedResponse = AIResponse(
            content: "Japanese translation",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        await vm.translate(
            originalText: "Hello world",
            locator: locator,
            format: .txt
        )
        #expect(stub.sendRequestCallCount == 2, "Different language should produce a new provider call")
        #expect(vm.translatedText == "Japanese translation")
    }

    // MARK: - Empty content shows error

    @Test @MainActor func emptyContentShowsError() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Should not reach",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.translate(
            originalText: "",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt
        )

        #expect(vm.errorMessage != nil)
        #expect(vm.translatedText == nil)
        #expect(vm.isLoading == false)
        #expect(stub.sendRequestCallCount == 0, "Provider should not be called with empty content")
    }

    // MARK: - Error shown on failure

    @Test @MainActor func errorShownOnFailure() async {
        let stub = StubAIProvider()
        stub.stubbedError = AIError.networkError("Connection refused")

        let (vm, _) = makeViewModel(provider: stub)

        await vm.translate(
            originalText: "Text to translate",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt
        )

        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("Connection refused") == true)
        #expect(vm.translatedText == nil)
        #expect(vm.isLoading == false)
    }

    // MARK: - Feature disabled shows error

    @Test @MainActor func featureDisabledShowsError() async {
        let (vm, _) = makeViewModel(featureEnabled: false)

        await vm.translate(
            originalText: "Text to translate",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt
        )

        #expect(vm.errorMessage != nil)
        #expect(vm.translatedText == nil)
    }

    // MARK: - Consent required shows error

    @Test @MainActor func consentRequiredShowsError() async {
        let (vm, _) = makeViewModel(hasConsent: false)

        await vm.translate(
            originalText: "Text to translate",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt
        )

        #expect(vm.errorMessage != nil)
        #expect(vm.translatedText == nil)
    }

    // MARK: - CJK source text works

    @Test @MainActor func cjkSourceTextTranslates() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "This is the translated text from Chinese",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)
        vm.targetLanguage = "English"

        await vm.translate(
            originalText: "这是一段中文文本，用于测试翻译功能。",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt
        )

        #expect(vm.translatedText == "This is the translated text from Chinese")
        #expect(vm.originalText == "这是一段中文文本，用于测试翻译功能。")
    }

    // MARK: - Reset clears all state

    @Test @MainActor func resetClearsAllState() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Translation",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.translate(
            originalText: "Some text",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt
        )
        #expect(vm.translatedText != nil)

        vm.reset()

        #expect(vm.originalText.isEmpty)
        #expect(vm.translatedText == nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)
    }

    // MARK: - Supported languages list

    @Test @MainActor func supportedLanguagesContainsExpected() {
        let (vm, _) = makeViewModel()

        let expected = ["Chinese", "Japanese", "Korean", "Spanish", "French",
                        "German", "Portuguese", "Russian", "Arabic"]

        for lang in expected {
            #expect(vm.supportedLanguages.contains(lang),
                    "\(lang) should be in supported languages")
        }
    }

    // MARK: - Long content is handled (truncated by context extractor)

    @Test @MainActor func longContentHandled() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Translation of long text",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        let longContent = String(repeating: "word ", count: 2000)

        await vm.translate(
            originalText: longContent,
            locator: WI11TestHelpers.makeLocator(),
            format: .txt
        )

        #expect(vm.translatedText == "Translation of long text")
        #expect(stub.sendRequestCallCount == 1)
    }
}
