// Purpose: Page turn animation types and transition logic.
// Supports none (instant), slide (translate X), and cover (3D transform).
// Respects UIAccessibility.isReduceMotionEnabled.
//
// Key decisions:
// - Enum-based API — no instances, all static methods.
// - Animations are UIView-based (UIView.animate).
// - Reduce motion collapses all animations to instant swap.
// - 300ms duration for slide and cover matches iOS conventions.
//
// @coordinates-with ReaderContainerView.swift, AutoPageTurner.swift

#if canImport(UIKit)
import UIKit

/// Available page turn animation styles.
enum PageTurnAnimation: String, Codable, Sendable, CaseIterable {
    case none
    case slide
    case cover
}

/// Performs page turn transitions between views.
enum PageTurnAnimator {

    // MARK: - Types

    enum Direction: Sendable, Equatable {
        case forward
        case backward
    }

    // MARK: - Duration

    /// Returns the animation duration for a given style.
    /// - Parameters:
    ///   - animation: The animation style.
    ///   - reduceMotion: Whether reduce-motion is active. Defaults to system setting.
    /// - Returns: Duration in seconds.
    static func duration(
        for animation: PageTurnAnimation,
        reduceMotion: Bool? = nil
    ) -> TimeInterval {
        let isReduced = reduceMotion ?? UIAccessibility.isReduceMotionEnabled
        if isReduced { return 0 }

        switch animation {
        case .none: return 0
        case .slide: return 0.3
        case .cover: return 0.3
        }
    }

    // MARK: - Transition

    /// Perform a page turn transition from one view to another.
    ///
    /// - Parameters:
    ///   - from: The current (outgoing) view.
    ///   - to: The new (incoming) view.
    ///   - animation: The animation style.
    ///   - direction: Forward or backward.
    ///   - reduceMotion: Override for reduce-motion check. Defaults to system setting.
    ///   - completion: Called when the transition finishes.
    @MainActor static func transition(
        from: UIView,
        to: UIView,
        animation: PageTurnAnimation,
        direction: Direction,
        reduceMotion: Bool? = nil,
        completion: @escaping @Sendable () -> Void
    ) {
        let dur = duration(for: animation, reduceMotion: reduceMotion)

        guard dur > 0 else {
            // Instant swap
            from.isHidden = true
            to.isHidden = false
            completion()
            return
        }

        let containerWidth = from.superview?.bounds.width ?? from.bounds.width
        let sign: CGFloat = direction == .forward ? 1 : -1

        switch animation {
        case .none:
            from.isHidden = true
            to.isHidden = false
            completion()

        case .slide:
            // Incoming view starts off-screen
            to.transform = CGAffineTransform(translationX: sign * containerWidth, y: 0)
            to.isHidden = false

            UIView.animate(withDuration: dur, delay: 0, options: .curveEaseInOut) {
                from.transform = CGAffineTransform(translationX: -sign * containerWidth, y: 0)
                to.transform = .identity
            } completion: { _ in
                from.isHidden = true
                from.transform = .identity
                completion()
            }

        case .cover:
            // Incoming view slides over outgoing with shadow
            to.transform = CGAffineTransform(translationX: sign * containerWidth, y: 0)
            to.layer.shadowColor = UIColor.black.cgColor
            to.layer.shadowOpacity = 0.3
            to.layer.shadowOffset = CGSize(width: -sign * 4, height: 0)
            to.layer.shadowRadius = 8
            to.isHidden = false

            UIView.animate(withDuration: dur, delay: 0, options: .curveEaseInOut) {
                to.transform = .identity
            } completion: { _ in
                from.isHidden = true
                to.layer.shadowOpacity = 0
                completion()
            }
        }
    }
}
#endif
