// Purpose: Protocol and default implementation for haptic feedback.
// Enables mock injection in tests.
//
// Key decisions:
// - Protocol enables DI for testability — mock records calls, real calls UIKit.
// - UIImpactFeedbackGenerator is safe on Simulator (no-ops, no crash).
// - @MainActor on protocol since UIKit feedback generators require main thread.
//
// @coordinates-with: ReaderNotificationHandlers.swift, ReaderNotificationModifier.swift

import UIKit

/// Protocol for haptic feedback, enabling mock injection in tests.
@MainActor
protocol HapticFeedbackProviding {
    /// Triggers a light impact haptic. Safe to call on Simulator (no-ops).
    func triggerLightImpact()
}

/// Default implementation wrapping UIImpactFeedbackGenerator(.light).
@MainActor
final class HapticFeedbackProvider: HapticFeedbackProviding {
    private let generator = UIImpactFeedbackGenerator(style: .light)

    func triggerLightImpact() {
        generator.impactOccurred()
    }
}
