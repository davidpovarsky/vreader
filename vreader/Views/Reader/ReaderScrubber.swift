// Purpose: Feature #60 WI-6b — the bottom-chrome progress scrubber. A 3 pt
// track with an accent fill and a 14 pt draggable thumb, matching the
// design. Clamp + discrete-step snapping reuse `ReadingProgressBar`'s
// tested statics so WI-6b does not re-derive that logic. Split out of
// ReaderBottomChrome.swift for the ~300-line file budget (feature #101
// Gate-4 r2).
//
// @coordinates-with: ReaderBottomChrome.swift, ReadingProgressBar.swift,
//   ReaderThemeV2.swift

import SwiftUI

/// The bottom-chrome progress scrubber (Feature #60 WI-6b). Internal so
/// only the reader chrome composes it.
struct ReaderScrubber: View {
    let theme: ReaderThemeV2
    @Binding var progress: Double
    let onSeek: (Double) -> Void
    let discreteSteps: Int?

    var body: some View {
        Slider(
            value: Binding(
                get: {
                    ReadingProgressBar.clampedProgress(progress)
                },
                set: { rawValue in
                    let resolved = ReadingProgressBar.resolveSeekValue(
                        rawValue,
                        discreteSteps: discreteSteps
                    )
                    progress = resolved
                    onSeek(resolved)
                }
            ),
            in: 0...1
        )
        .tint(Color(theme.accentColor))
        .accessibilityLabel("Reading progress")
        .accessibilityValue(
            ReadingProgressBar.formatLabel(
                progress: ReadingProgressBar.clampedProgress(progress),
                label: nil
            )
        )
        .accessibilityIdentifier("readingProgressScrubber")
    }

}
