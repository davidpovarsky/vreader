// Purpose: Narrow app-level reader navigation seam for Feature #177 tools.

import Foundation

protocol AIReaderNavigationRouting: Sendable {
    func navigate(to locator: Locator, session: AIDocumentSessionID) async -> Bool
    func openBook(fingerprintKey: String, locator: Locator?) async -> Bool
}

struct AIBookOpenNavigationRequest: Sendable {
    let id: UUID
    let fingerprintKey: String
    let locator: Locator?
}

extension Notification.Name {
    static let aiOpenBookRequested = Notification.Name("vreader.aiOpenBookRequested")
}

actor AIPendingBookNavigationStore {
    static let shared = AIPendingBookNavigationStore()
    private struct PendingTarget: Sendable {
        let locator: Locator
        var claimedReaderToken: UUID?
    }
    private var targets: [String: PendingTarget] = [:]

    func set(_ locator: Locator?, for fingerprintKey: String) {
        if let locator {
            targets[fingerprintKey] = PendingTarget(
                locator: locator, claimedReaderToken: nil
            )
        }
        else { targets.removeValue(forKey: fingerprintKey) }
    }

    func claim(fingerprintKey: String, readerToken: UUID) {
        guard var target = targets[fingerprintKey],
              target.claimedReaderToken == nil else { return }
        target.claimedReaderToken = readerToken
        targets[fingerprintKey] = target
    }

    func take(for fingerprintKey: String, readerToken: UUID) -> Locator? {
        guard targets[fingerprintKey]?.claimedReaderToken == readerToken else {
            return nil
        }
        return targets.removeValue(forKey: fingerprintKey)?.locator
    }
}

struct NotificationAIReaderNavigationRouter: AIReaderNavigationRouting, @unchecked Sendable {
    let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func navigate(to locator: Locator, session: AIDocumentSessionID) async -> Bool {
        guard !Task.isCancelled,
              locator.bookFingerprint.canonicalKey == session.fingerprintKey else {
            return false
        }
        await MainActor.run {
            notificationCenter.post(
                name: .readerNavigateToLocator,
                object: locator,
                userInfo: ["readerToken": session.readerToken]
            )
        }
        return !Task.isCancelled
    }

    func openBook(fingerprintKey: String, locator: Locator?) async -> Bool {
        guard !Task.isCancelled,
              locator?.bookFingerprint.canonicalKey == fingerprintKey || locator == nil else {
            return false
        }
        let request = AIBookOpenNavigationRequest(
            id: UUID(), fingerprintKey: fingerprintKey, locator: locator
        )
        await MainActor.run {
            notificationCenter.post(name: .aiOpenBookRequested, object: request)
        }
        return !Task.isCancelled
    }
}

enum AIReaderNavigationTarget {
    static func accepts(
        _ notification: Notification,
        readerToken: UUID?
    ) -> Bool {
        guard let target = notification.userInfo?["readerToken"] as? UUID else {
            return true
        }
        return readerToken == target
    }
}
