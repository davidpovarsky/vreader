// Purpose: Custom overlay toolbar for reader screens.
//
// Replaces the system NavigationBar so that content position is always stable.
// System nav bar changes safe area when toggled, causing content to shift —
// this overlay floats on top without affecting layout. (bug #62 v3)
//
// Styling matches the bottom bar (ReaderBottomOverlay, ReadingProgressBar):
// theme-based background at 0.92 opacity, 16pt horizontal padding. (bug #71)
//
// Uses UIWindowScene safe area (not GeometryReader) because the parent view
// has .ignoresSafeArea(.top) which zeroes GeometryReader insets. (bug #73)
//
// @coordinates-with ReaderContainerView.swift

import SwiftUI

/// Custom reader toolbar that floats as an overlay — no safe area impact.
struct ReaderChromeBar: View {
    let onBack: () -> Void
    let onSearch: () -> Void
    let onBookmark: () -> Void
    let onAnnotations: () -> Void
    let onAI: (() -> Void)?
    let onTTS: (() -> Void)?
    let onSettings: () -> Void
    let backgroundColor: Color
    let foregroundColor: Color
    let ttsActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Safe area fill — extends background under notch/Dynamic Island
            backgroundColor.opacity(0.92)
                .frame(height: Self.windowSafeAreaTop)

            // Toolbar content — 44pt standard height
            HStack(spacing: 0) {
                chromeButton(systemName: "chevron.left", label: "Back to library", id: "readerBackButton", action: onBack)

                Spacer()

                HStack(spacing: 4) {
                    chromeButton(systemName: "magnifyingglass", label: "Search in book", id: "readerSearchButton", action: onSearch)
                    chromeButton(systemName: "bookmark", label: "Add bookmark", id: "readerBookmarkButton", action: onBookmark)
                    chromeButton(systemName: "list.bullet.rectangle", label: "Bookmarks and annotations", id: "readerAnnotationsButton", action: onAnnotations)

                    if let onAI {
                        chromeButton(systemName: "sparkles", label: "AI Assistant", id: "readerAIButton", action: onAI)
                    }

                    if let onTTS {
                        chromeButton(
                            systemName: ttsActive ? "speaker.wave.2.fill" : "speaker.wave.2",
                            label: ttsActive ? "TTS active" : "Read aloud",
                            id: "readerTTSButton",
                            action: onTTS
                        )
                    }

                    chromeButton(systemName: "textformat.size", label: "Reading settings", id: "readerSettingsButton", action: onSettings)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(backgroundColor.opacity(0.92))

            Spacer()
        }
    }

    /// Standard 44x44 touch-target button with consistent icon sizing.
    private func chromeButton(systemName: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(foregroundColor)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// Real top safe area inset from UIWindowScene.
    /// GeometryReader returns 0 when parent has .ignoresSafeArea(.top). (bug #73)
    private static var windowSafeAreaTop: CGFloat {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow })
        else { return 59 } // Fallback for Dynamic Island devices
        return window.safeAreaInsets.top
    }
}
