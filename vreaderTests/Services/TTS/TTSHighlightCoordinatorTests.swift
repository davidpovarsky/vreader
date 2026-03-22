// Purpose: Tests for TTSHighlightCoordinator — sentence tokenization,
// highlight range mapping, and auto-scroll integration.
//
// @coordinates-with: TTSHighlightCoordinator.swift, TTSService.swift, TextReaderUIState.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("TTSHighlightCoordinator")
@MainActor
struct TTSHighlightCoordinatorTests {

    // MARK: - Sentence Tokenization

    @Test("tokenizes English sentences")
    func tokenizeEnglish() {
        let text = "Hello world. This is a test. Another sentence here."
        let ranges = TTSHighlightCoordinator.tokenizeSentences(in: text)
        #expect(ranges.count >= 3, "Should detect at least 3 sentences")
    }

    @Test("tokenizes CJK sentences")
    func tokenizeCJK() {
        let text = "这是第一句话。这是第二句话。这是第三句话。"
        let ranges = TTSHighlightCoordinator.tokenizeSentences(in: text)
        #expect(ranges.count >= 3, "Should detect at least 3 CJK sentences")
    }

    @Test("tokenizes mixed language text")
    func tokenizeMixed() {
        let text = "Hello world. 这是中文。Another sentence."
        let ranges = TTSHighlightCoordinator.tokenizeSentences(in: text)
        #expect(ranges.count >= 2, "Should detect mixed-language sentences")
    }

    @Test("empty text returns no sentences")
    func tokenizeEmpty() {
        let ranges = TTSHighlightCoordinator.tokenizeSentences(in: "")
        #expect(ranges.isEmpty)
    }

    // MARK: - Sentence Range Lookup

    @Test("sentenceRange returns correct range for offset within sentence")
    func sentenceRangeLookup() {
        let tts = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        let uiState = TextReaderUIState()
        let coordinator = TTSHighlightCoordinator(ttsService: tts, uiState: uiState)

        let text = "Hello world. This is a test."
        coordinator.configure(text: text)

        // Offset 0 should be in the first sentence
        let range = coordinator.sentenceRange(containing: 0)
        #expect(range != nil, "Should find sentence for offset 0")
        #expect(range!.location == 0, "First sentence should start at 0")
    }

    @Test("sentenceRange returns nil for out-of-bounds offset")
    func sentenceRangeOutOfBounds() {
        let tts = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        let uiState = TextReaderUIState()
        let coordinator = TTSHighlightCoordinator(ttsService: tts, uiState: uiState)

        coordinator.configure(text: "Hello.")
        let range = coordinator.sentenceRange(containing: 9999)
        #expect(range == nil, "Out-of-bounds offset should return nil")
    }

    // MARK: - UI State Updates

    @Test("updateHighlight sets highlightRange when TTS is speaking")
    func updateHighlightSetRange() {
        let tts = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        let uiState = TextReaderUIState()
        let coordinator = TTSHighlightCoordinator(ttsService: tts, uiState: uiState)

        let text = "Hello world. This is a test."
        coordinator.configure(text: text)

        // Start speaking to set state
        tts.startSpeaking(text: text)
        // Simulate word position update
        coordinator.updateHighlight(offset: 0)

        #expect(uiState.highlightRange != nil, "Should set highlight range when speaking")
        #expect(uiState.scrollToOffset != nil, "Should set scroll offset when speaking")
    }

    @Test("clearHighlight removes temporary highlight")
    func clearHighlightRemovesRange() {
        let tts = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        let uiState = TextReaderUIState()
        let coordinator = TTSHighlightCoordinator(ttsService: tts, uiState: uiState)

        uiState.highlightRange = NSRange(location: 0, length: 10)
        uiState.highlightIsTemporary = true

        coordinator.clearHighlight()
        #expect(uiState.highlightRange == nil, "Should clear temporary highlight")
    }

    @Test("clearHighlight preserves persistent highlight")
    func clearHighlightPreservesPersistent() {
        let tts = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        let uiState = TextReaderUIState()
        let coordinator = TTSHighlightCoordinator(ttsService: tts, uiState: uiState)

        uiState.highlightRange = NSRange(location: 0, length: 10)
        uiState.highlightIsTemporary = false

        coordinator.clearHighlight()
        #expect(uiState.highlightRange != nil, "Should NOT clear persistent highlight")
    }
}
#endif
