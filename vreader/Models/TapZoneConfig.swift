// Purpose: Defines tap zone configuration for reader screens.
// The reader divides the screen into three horizontal zones (left/center/right),
// each mapped to a configurable action (previous page, toggle chrome, next page, none).
//
// Key decisions:
// - Zones are percentage-based: 33.33% / 33.33% / 33.33%.
// - Zone detection is a static pure function for easy testing.
// - All types are Codable + Sendable for persistence and thread safety.
// - previousPage/nextPage are no-ops until Phase B wires PageNavigator.
// - TapZoneStore provides @Observable persistence independent of ReaderSettingsStore.
//
// @coordinates-with TapZoneOverlay.swift, ReaderContainerView.swift

import Foundation
import SwiftUI

/// Identifies which horizontal third of the screen a tap landed in.
enum TapZone: String, Codable, Sendable {
    case left
    case center
    case right
}

/// Actions that can be assigned to a tap zone.
enum TapAction: String, Codable, Sendable, CaseIterable {
    case previousPage
    case nextPage
    case toggleChrome
    case none
}

/// Configurable mapping of tap zones to actions.
struct TapZoneConfig: Codable, Sendable, Equatable {
    var leftAction: TapAction
    var centerAction: TapAction
    var rightAction: TapAction

    static let `default` = TapZoneConfig(
        leftAction: .previousPage,
        centerAction: .toggleChrome,
        rightAction: .nextPage
    )

    init(
        leftAction: TapAction = .previousPage,
        centerAction: TapAction = .toggleChrome,
        rightAction: TapAction = .nextPage
    ) {
        self.leftAction = leftAction
        self.centerAction = centerAction
        self.rightAction = rightAction
    }

    func action(for zone: TapZone) -> TapAction {
        switch zone {
        case .left: return leftAction
        case .center: return centerAction
        case .right: return rightAction
        }
    }

    static func zone(atX x: CGFloat, totalWidth: CGFloat) -> TapZone {
        guard totalWidth > 0 else { return .center }
        let fraction = x / totalWidth
        if fraction < 1.0 / 3.0 {
            return .left
        } else if fraction < 2.0 / 3.0 {
            return .center
        } else {
            return .right
        }
    }
}

/// Observable store for tap zone configuration.
@Observable
@MainActor
final class TapZoneStore {
    static let key = "readerTapZoneConfig"

    var config: TapZoneConfig {
        didSet {
            if let data = try? JSONEncoder().encode(config) {
                defaults.set(data, forKey: Self.key)
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(TapZoneConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
    }
}
