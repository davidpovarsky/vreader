// Purpose: Manages text-to-speech playback using AVSpeechSynthesizer (or mock).
// Tracks state (idle/speaking/paused), current reading position (UTF-16 offset),
// and speech rate. Provides static helper to extract text from ReflowableTextSource.
//
// Key decisions:
// - @MainActor @Observable for SwiftUI data binding.
// - SpeechSynthesizing protocol injection for testability (no real audio in tests).
// - Rate clamped to 0.0...1.0 (AVSpeechUtterance valid range).
// - Empty/whitespace-only text is a no-op (stays idle).
// - Negative fromOffset clamped to 0; offset beyond text length is a no-op.
// - Position tracking via simulateWillSpeakRange (called by delegate in production).
//
// @coordinates-with: SpeechSynthesizing.swift, TTSControlBar.swift,
//   ReaderContainerView.swift, ReflowableTextSource.swift

import AVFoundation
import Foundation

@MainActor @Observable
final class TTSService: NSObject {

    // MARK: - State

    enum State: Sendable, Equatable {
        case idle
        case speaking
        case paused
    }

    private(set) var state: State = .idle
    private(set) var currentOffsetUTF16: Int = 0

    /// Speech rate in AVSpeechUtterance range (0.0–1.0). Clamped on set.
    var rate: Float = 0.5 {
        didSet { rate = min(max(rate, 0.0), 1.0) }
    }

    // MARK: - Private

    private let synthesizer: SpeechSynthesizing
    private var baseOffsetUTF16: Int = 0

    // MARK: - Init

    /// Creates a TTSService with a synthesizer factory for dependency injection.
    /// In production, pass `{ SystemSpeechSynthesizer() }`.
    /// In tests, pass `{ MockSpeechSynthesizer() }`.
    init(synthesizerFactory: () -> SpeechSynthesizing = { SystemSpeechSynthesizer() }) {
        self.synthesizer = synthesizerFactory()
        super.init()

        // Wire delegate if using SystemSpeechSynthesizer
        if let system = synthesizer as? SystemSpeechSynthesizer {
            system.delegateTarget = self
        }
    }

    // MARK: - Public API

    /// Starts speaking the given text from the specified UTF-16 offset.
    /// Empty or whitespace-only text is a no-op. Negative offset clamped to 0.
    /// Offset beyond text length is a no-op.
    func startSpeaking(text: String, fromOffset: Int = 0) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let clampedOffset = max(fromOffset, 0)

        // Validate offset is within text
        let utf16Count = text.utf16.count
        guard clampedOffset < utf16Count else { return }

        // Stop any current speech
        synthesizer.stopSpeaking()

        // Extract substring from offset
        let startIndex = text.utf16.index(text.utf16.startIndex, offsetBy: clampedOffset)
        let substring = String(text.utf16[startIndex...])!

        baseOffsetUTF16 = clampedOffset
        currentOffsetUTF16 = clampedOffset

        // Create utterance
        let utterance = AVSpeechUtterance(string: substring)
        utterance.rate = rate
        synthesizer.speak(utterance)
        state = .speaking
    }

    /// Pauses speech. No-op if not currently speaking.
    func pause() {
        guard state == .speaking else { return }
        synthesizer.pauseSpeaking()
        state = .paused
    }

    /// Resumes paused speech. No-op if not currently paused.
    func resume() {
        guard state == .paused else { return }
        synthesizer.continueSpeaking()
        state = .speaking
    }

    /// Stops speech and returns to idle. No-op if already idle.
    func stop() {
        guard state != .idle else { return }
        synthesizer.stopSpeaking()
        state = .idle
        currentOffsetUTF16 = 0
        baseOffsetUTF16 = 0
    }

    // MARK: - Position Tracking

    /// Called by the speech synthesizer delegate when it is about to speak a range.
    /// `location` and `length` are relative to the utterance text.
    /// `fromOffset` is the base offset to add (= baseOffsetUTF16 in production).
    func simulateWillSpeakRange(location: Int, length: Int, fromOffset: Int) {
        currentOffsetUTF16 = fromOffset + location
    }

    // MARK: - Text Extraction

    /// Extracts text from a ReflowableTextSource starting at the given UTF-16 offset.
    /// Returns the substring from `startOffset` to the end, or empty string if out of range.
    static func extractText(from source: some ReflowableTextSource, startOffset: Int) -> String {
        let fullText = source.fullText
        guard startOffset >= 0, startOffset < fullText.utf16.count else {
            return ""
        }
        let startIdx = fullText.utf16.index(fullText.utf16.startIndex, offsetBy: startOffset)
        return String(fullText.utf16[startIdx...]) ?? ""
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSService: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let location = characterRange.location
        let length = characterRange.length
        Task { @MainActor in
            self.simulateWillSpeakRange(
                location: location,
                length: length,
                fromOffset: self.baseOffsetUTF16
            )
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.state = .idle
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.state = .idle
        }
    }
}
