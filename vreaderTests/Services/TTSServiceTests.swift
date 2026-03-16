// Purpose: Tests for TTSService — TTS read aloud using AVSpeechSynthesizer.
// Validates state transitions, speed control, position tracking, and format checks.
//
// Key decisions:
// - Uses a MockSynthesizer protocol to avoid real AVSpeechSynthesizer in tests.
// - Tests run synchronously via direct state inspection (no async waits on speech).
// - Edge cases: empty text, format availability, rapid state changes, CJK text.

import Testing
import Foundation
@testable import vreader

// MARK: - TTSService State Transition Tests

@Suite("TTSService State Transitions")
struct TTSServiceStateTransitionTests {

    @Test @MainActor
    func startSpeaking_beginsFromCurrentPosition() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello, world!", fromOffset: 5)
        #expect(service.state == .speaking)
        #expect(service.currentOffsetUTF16 == 5)
    }

    @Test @MainActor
    func startSpeaking_fromZeroOffset_defaultParameter() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello")
        #expect(service.state == .speaking)
        #expect(service.currentOffsetUTF16 == 0)
    }

    @Test @MainActor
    func pauseSpeech_pausesSynthesizer() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello, world!")
        service.pause()
        #expect(service.state == .paused)
    }

    @Test @MainActor
    func resumeSpeech_continuesSpeaking() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello, world!")
        service.pause()
        service.resume()
        #expect(service.state == .speaking)
    }

    @Test @MainActor
    func stopSpeech_stopsSynthesizer() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello, world!")
        service.stop()
        #expect(service.state == .idle)
    }

    @Test @MainActor
    func pause_whenIdle_remainsIdle() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.pause()
        #expect(service.state == .idle)
    }

    @Test @MainActor
    func resume_whenIdle_remainsIdle() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.resume()
        #expect(service.state == .idle)
    }

    @Test @MainActor
    func stop_whenAlreadyIdle_remainsIdle() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.stop()
        #expect(service.state == .idle)
    }

    @Test @MainActor
    func startSpeaking_whileAlreadySpeaking_restarts() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "First text")
        service.startSpeaking(text: "Second text", fromOffset: 10)
        #expect(service.state == .speaking)
        #expect(service.currentOffsetUTF16 == 10)
    }
}

// MARK: - Speed Control Tests

@Suite("TTSService Speed Control")
struct TTSServiceSpeedControlTests {

    @Test @MainActor
    func speedControl_defaultRate() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        #expect(service.rate == 0.5)
    }

    @Test @MainActor
    func speedControl_setsRate_low() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.rate = 0.25
        #expect(service.rate == 0.25)
    }

    @Test @MainActor
    func speedControl_setsRate_high() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.rate = 0.75
        #expect(service.rate == 0.75)
    }

    @Test @MainActor
    func speedControl_clampsAboveMax() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.rate = 1.5
        #expect(service.rate == 1.0, "Rate should be clamped to 1.0 max")
    }

    @Test @MainActor
    func speedControl_clampsBelowMin() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.rate = -0.1
        #expect(service.rate == 0.0, "Rate should be clamped to 0.0 min")
    }

    @Test @MainActor
    func speedControl_rateAppliedToUtterance() async {
        let mock = MockSpeechSynthesizer()
        let service = TTSService(synthesizerFactory: { mock })
        service.rate = 0.75
        service.startSpeaking(text: "Test text")
        #expect(mock.lastUtteranceRate == 0.75, "Utterance rate should match service rate")
    }
}

// MARK: - Position Tracking Tests

@Suite("TTSService Position Tracking")
struct TTSServicePositionTrackingTests {

    @Test @MainActor
    func positionTracking_initialOffset() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        #expect(service.currentOffsetUTF16 == 0)
    }

    @Test @MainActor
    func positionTracking_updatesCurrentOffset() async {
        let mock = MockSpeechSynthesizer()
        let service = TTSService(synthesizerFactory: { mock })
        service.startSpeaking(text: "Hello, world!")

        // Simulate delegate callback for position tracking
        service.simulateWillSpeakRange(location: 7, length: 5, fromOffset: 0)
        #expect(service.currentOffsetUTF16 == 7)
    }

    @Test @MainActor
    func positionTracking_withNonZeroStartOffset() async {
        let mock = MockSpeechSynthesizer()
        let service = TTSService(synthesizerFactory: { mock })
        service.startSpeaking(text: "Hello, world!", fromOffset: 100)

        // Simulate delegate: range is relative to utterance text, offset adds base
        service.simulateWillSpeakRange(location: 7, length: 5, fromOffset: 100)
        #expect(service.currentOffsetUTF16 == 107)
    }
}

// MARK: - Text Extraction Tests

@Suite("TTSService Text Extraction")
struct TTSServiceTextExtractionTests {

    @Test @MainActor
    func textExtraction_fromReflowableSource() async {
        let source = TXTReflowableTextSource(textContent: "Hello, this is reflowable text.")
        let text = TTSService.extractText(from: source, startOffset: 0)
        #expect(text == "Hello, this is reflowable text.")
    }

    @Test @MainActor
    func textExtraction_fromReflowableSource_withOffset() async {
        let fullText = "Hello, world!"
        let source = TXTReflowableTextSource(textContent: fullText)
        let text = TTSService.extractText(from: source, startOffset: 7)
        #expect(text == "world!")
    }

    @Test @MainActor
    func textExtraction_fromReflowableSource_offsetAtEnd() async {
        let source = TXTReflowableTextSource(textContent: "Hello")
        let text = TTSService.extractText(from: source, startOffset: 5)
        #expect(text == "", "Offset at end should return empty string")
    }

    @Test @MainActor
    func textExtraction_fromReflowableSource_cjkText() async {
        let cjk = "你好世界，这是一段中文文本。"
        let source = TXTReflowableTextSource(textContent: cjk)
        let text = TTSService.extractText(from: source, startOffset: 0)
        #expect(text == cjk)
    }
}

// MARK: - Edge Case Tests

@Suite("TTSService Edge Cases")
struct TTSServiceEdgeCaseTests {

    @Test @MainActor
    func emptyText_doesNotCrash() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "")
        #expect(service.state == .idle, "Empty text should not start speaking")
    }

    @Test @MainActor
    func whitespaceOnlyText_doesNotSpeak() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "   \n\t  ")
        #expect(service.state == .idle, "Whitespace-only text should not start speaking")
    }

    @Test @MainActor
    func formatWithoutTTS_returnsUnavailable() async {
        let caps = FormatCapabilities.capabilities(for: .pdf)
        #expect(!caps.contains(.tts), "PDF should not have TTS capability")
    }

    @Test @MainActor
    func formatWithTTS_txt_returnsAvailable() async {
        let caps = FormatCapabilities.capabilities(for: .txt)
        #expect(caps.contains(.tts), "TXT should have TTS capability")
    }

    @Test @MainActor
    func formatWithTTS_md_returnsAvailable() async {
        let caps = FormatCapabilities.capabilities(for: .md)
        #expect(caps.contains(.tts), "MD should have TTS capability")
    }

    @Test @MainActor
    func formatWithTTS_epub_returnsAvailable() async {
        let caps = FormatCapabilities.capabilities(for: .epub)
        #expect(caps.contains(.tts), "EPUB should have TTS capability")
    }

    @Test @MainActor
    func rapidStartStop_doesNotCrash() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        for _ in 0..<10 {
            service.startSpeaking(text: "Rapid test")
            service.stop()
        }
        #expect(service.state == .idle)
    }

    @Test @MainActor
    func rapidPauseResume_doesNotCrash() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Rapid test")
        for _ in 0..<10 {
            service.pause()
            service.resume()
        }
        #expect(service.state == .speaking)
    }

    @Test @MainActor
    func stopAfterPause_goesToIdle() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello")
        service.pause()
        #expect(service.state == .paused)
        service.stop()
        #expect(service.state == .idle)
    }

    @Test @MainActor
    func startSpeaking_cjkText_works() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "你好世界，这是一段中文。")
        #expect(service.state == .speaking)
    }

    @Test @MainActor
    func startSpeaking_emojiText_works() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello 🌍🎉 World")
        #expect(service.state == .speaking)
    }

    @Test @MainActor
    func negativeOffset_treatedAsZero() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello", fromOffset: -5)
        #expect(service.currentOffsetUTF16 == 0, "Negative offset should be clamped to 0")
    }

    @Test @MainActor
    func offsetBeyondText_doesNotCrash() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hi", fromOffset: 1000)
        #expect(service.state == .idle, "Offset beyond text length should not start speaking")
    }
}

// MARK: - Mock

/// Minimal mock for AVSpeechSynthesizer to use in unit tests.
/// Tracks method calls and utterance properties without requiring audio hardware.
final class MockSpeechSynthesizer: SpeechSynthesizing {
    private(set) var speakCalled = false
    private(set) var pauseCalled = false
    private(set) var resumeCalled = false
    private(set) var stopCalled = false
    private(set) var lastUtteranceRate: Float?
    private(set) var lastUtteranceText: String?

    var isSpeaking: Bool = false
    var isPaused: Bool = false

    func speak(_ utterance: SpeechUtteranceProtocol) {
        speakCalled = true
        isSpeaking = true
        isPaused = false
        lastUtteranceRate = utterance.rate
        lastUtteranceText = utterance.speechString
    }

    func pauseSpeaking() -> Bool {
        pauseCalled = true
        if isSpeaking {
            isPaused = true
            isSpeaking = false
            return true
        }
        return false
    }

    func continueSpeaking() -> Bool {
        resumeCalled = true
        if isPaused {
            isSpeaking = true
            isPaused = false
            return true
        }
        return false
    }

    func stopSpeaking() -> Bool {
        stopCalled = true
        isSpeaking = false
        isPaused = false
        return true
    }
}
