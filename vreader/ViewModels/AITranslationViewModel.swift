// Purpose: ViewModel for AI-powered translation with bilingual display.
// Manages translation state, language selection, and caching through AIService.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Stores both originalText and translatedText for bilingual display.
// - Uses AIService for the full gate sequence (feature flag, consent, API key, cache).
// - Context extraction uses AIContextExtractor (same as summarize).
// - Caching is built into AIService — same content + language uses cache.
// - Default target language is "Chinese" (most common for CJK users).
//
// @coordinates-with: AIService.swift, TranslationPanel.swift, BilingualView.swift

import Foundation

/// ViewModel for AI-powered translation with bilingual view support.
@Observable
@MainActor
final class AITranslationViewModel {

    // MARK: - Published State

    /// The original text that was sent for translation.
    var originalText: String = ""

    /// The translated text result (nil before first translation).
    var translatedText: String?

    /// The currently selected target language.
    var targetLanguage: String = "Chinese"

    /// Whether a translation request is in progress.
    private(set) var isLoading: Bool = false

    /// Error message to display, or nil if no error.
    private(set) var errorMessage: String?

    /// List of supported target languages.
    let supportedLanguages: [String] = [
        "Chinese", "Japanese", "Korean", "Spanish", "French",
        "German", "Portuguese", "Russian", "Arabic"
    ]

    // MARK: - Dependencies

    private let aiService: AIService
    private let contextExtractor: AIContextExtractor

    // MARK: - Init

    init(
        aiService: AIService,
        contextExtractor: AIContextExtractor = AIContextExtractor()
    ) {
        self.aiService = aiService
        self.contextExtractor = contextExtractor
    }

    // MARK: - Actions

    /// Translates the given text into the currently selected target language.
    ///
    /// - Parameters:
    ///   - originalText: The text to translate.
    ///   - locator: The reading position for context extraction.
    ///   - format: The book format.
    func translate(
        originalText: String,
        locator: Locator,
        format: BookFormat
    ) async {
        self.originalText = originalText
        self.translatedText = nil
        self.errorMessage = nil
        self.isLoading = true

        let context = contextExtractor.extractContext(
            locator: locator,
            textContent: originalText,
            format: format
        )

        guard !context.isEmpty else {
            isLoading = false
            errorMessage = AIError.contextExtractionFailed.localizedDescription
            return
        }

        let request = AIRequest(
            actionType: .translate,
            bookFingerprint: locator.bookFingerprint,
            locator: locator,
            contextText: context,
            userPrompt: nil,
            targetLanguage: targetLanguage,
            promptVersion: "v1"
        )

        do {
            let response = try await aiService.sendRequest(request)
            translatedText = response.content
        } catch let error as AIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Resets all state to initial values.
    func reset() {
        originalText = ""
        translatedText = nil
        errorMessage = nil
        isLoading = false
    }
}
