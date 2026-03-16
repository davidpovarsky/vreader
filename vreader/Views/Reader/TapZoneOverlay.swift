// Purpose: Tap zone dispatch and overlay modifier for reader screens.
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
struct TapZoneModifier: ViewModifier {
    let config: TapZoneConfig

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            ZStack {
                content
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
            }
        }
    }
}

extension View {
    func tapZoneOverlay(config: TapZoneConfig) -> some View {
        modifier(TapZoneModifier(config: config))
    }
}
