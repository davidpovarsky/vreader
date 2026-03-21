// Purpose: Tap zone dispatch and overlay modifier for reader screens.
//
// IMPORTANT: Only used for the UNIFIED renderer (SwiftUI-native scroll views).
// Native mode readers (UITextView, WKWebView, PDFView) handle taps via their own
// UITapGestureRecognizer / JS click handler. Do NOT apply tapZoneOverlay to native
// readers — the Color.clear overlay blocks scroll gestures from reaching UIKit. (bug #70)
//
// @coordinates-with TapZoneConfig.swift, ReaderContainerView.swift, ReaderNotifications.swift

import SwiftUI

/// Dispatches tap zone actions via NotificationCenter.
enum TapZoneDispatcher {
    static func dispatch(_ action: TapAction) {
        switch action {
        case .toggleChrome:
            NotificationCenter.default.post(name: .readerContentTapped, object: nil)
        case .previousPage:
            NotificationCenter.default.post(name: .readerPreviousPage, object: nil)
        case .nextPage:
            NotificationCenter.default.post(name: .readerNextPage, object: nil)
        case .none:
            break
        }
    }
}

/// View modifier that overlays tap zone detection on reader content.
///
/// The overlay only covers the READING area (full height minus `bottomInset`).
/// The bottom `bottomInset` points pass touches directly to interactive controls
/// (progress bar Slider, bottom overlay) without interference. (bug #63)
struct TapZoneModifier: ViewModifier {
    let config: TapZoneConfig
    /// Height of bottom controls to exclude from the tap-zone overlay.
    /// Defaults to 100pt — covers ReadingProgressBar (~60pt) + ReaderBottomOverlay (~36pt).
    var bottomInset: CGFloat = 100

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            ZStack {
                content
                VStack(spacing: 0) {
                    // Reading surface — handles tap zone detection
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let zone = TapZoneConfig.zone(
                                atX: location.x,
                                totalWidth: geometry.size.width
                            )
                            TapZoneDispatcher.dispatch(config.action(for: zone))
                        }
                        .accessibilityIdentifier("tapZoneOverlay")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Reading area")
                        .accessibilityHint(
                            "Tap left for previous page, center to toggle toolbar, right for next page"
                        )
                    // Bottom exclusion zone — passes all touches through to progress bar and controls
                    Color.clear
                        .frame(height: bottomInset)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

extension View {
    func tapZoneOverlay(config: TapZoneConfig, bottomInset: CGFloat = 100) -> some View {
        modifier(TapZoneModifier(config: config, bottomInset: bottomInset))
    }
}
