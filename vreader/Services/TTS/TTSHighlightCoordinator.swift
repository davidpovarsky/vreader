// Purpose: Bridges TTS playback position to text highlighting and auto-scroll.
// Observes TTSService.currentOffsetUTF16 and maps word positions to sentence
// ranges, then updates TextReaderUIState for visual highlighting and scrolling.
//
// Key decisions:
// - Sentence tokenization via NLTokenizer (robust for CJK, Latin, mixed text).
// - Updates highlightRange (for HighlightableTextView rendering).
// - Updates scrollToOffset (for TXTTextViewBridge auto-scroll).
// - TXT/MD only — EPUB/PDF deferred (they use web views, not TextKit).
// - Operates on @MainActor since both TTSService and TextReaderUIState are @MainActor.
//
// @coordinates-with: TTSService.swift, TextReaderUIState.swift,
//   TXTReaderContainerView.swift, MDReaderContainerView.swift

#if canImport(UIKit)
import Foundation
import NaturalLanguage

/// Coordinates TTS playback position with text highlighting and auto-scroll.
/// Feature #40 (sentence highlight) and #41 (auto-scroll).
@MainActor
final class TTSHighlightCoordinator {

    private let ttsService: TTSService
    private let uiState: TextReaderUIState

    /// Full source text (UTF-16) for sentence boundary detection.
    private var sourceText: String?
    /// Cached sentence ranges (UTF-16 NSRange) for the current source text.
    private var sentenceRanges: [NSRange] = []

    init(ttsService: TTSService, uiState: TextReaderUIState) {
        self.ttsService = ttsService
        self.uiState = uiState
    }

    /// Sets the source text and pre-computes sentence boundaries.
    func configure(text: String) {
        sourceText = text
        sentenceRanges = Self.tokenizeSentences(in: text)
    }

    /// Called when TTS position updates (e.g., from an observation or onChange).
    /// Maps the word-level offset to a sentence range and updates UI state.
    func updateHighlight(offset: Int) {
        guard ttsService.state == .speaking else {
            clearHighlight()
            return
        }
        guard let range = sentenceRange(containing: offset) else { return }

        // Feature #40: highlight the current sentence
        uiState.highlightRange = range
        uiState.highlightIsTemporary = true

        // Feature #41: auto-scroll to keep the sentence visible
        uiState.scrollToOffset = range.location
    }

    /// Clears TTS highlight when playback stops or pauses.
    func clearHighlight() {
        if uiState.highlightIsTemporary {
            uiState.highlightRange = nil
        }
    }

    // MARK: - Sentence Detection

    /// Returns the sentence NSRange (UTF-16) containing the given UTF-16 offset.
    func sentenceRange(containing utf16Offset: Int) -> NSRange? {
        // Binary search for the sentence containing this offset
        var lo = 0, hi = sentenceRanges.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let range = sentenceRanges[mid]
            if utf16Offset < range.location {
                hi = mid - 1
            } else if utf16Offset >= range.location + range.length {
                lo = mid + 1
            } else {
                return range
            }
        }
        return nil
    }

    /// Tokenizes text into sentence ranges using NLTokenizer.
    static func tokenizeSentences(in text: String) -> [NSRange] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ranges: [NSRange] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let nsRange = NSRange(tokenRange, in: text)
            ranges.append(nsRange)
            return true
        }
        return ranges
    }
}
#endif
