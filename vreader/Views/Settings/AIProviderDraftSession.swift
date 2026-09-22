// Purpose: Process-lifetime draft storage for the AI provider editor.
//
// SwiftUI may tear down and recreate the provider sheet when the app moves
// between foreground/background or when the presentation hierarchy is rebuilt.
// The editor's form values used to live only in @State, so a rebuild reset the
// Add Provider form and made it impossible to switch apps to copy/paste an API
// key.
//
// This store keeps only the unsaved editor draft in memory. It deliberately
// does NOT persist to UserDefaults or disk. In particular, the API key remains
// memory-only until the user explicitly saves the provider, at which point the
// normal Keychain path takes over.
//
// Drafts are discarded only on explicit Cancel or a successful Save. A system
// presentation rebuild therefore restores the same values instead of starting
// a new blank form.

import Foundation

struct AIProviderDraftSnapshot: Equatable {
    let profileID: UUID
    var name: String
    var kind: ProviderKind
    var baseURLText: String
    var model: String
    var temperature: Double
    var maxTokens: Int
    var apiKey: String
    var isAPIKeySaved: Bool
}

/// Small in-memory session store. Access is synchronized because SwiftUI view
/// construction is not guaranteed to stay on one executor even though the
/// editor itself is UI-driven.
final class AIProviderDraftSession: @unchecked Sendable {
    static let shared = AIProviderDraftSession()

    private let lock = NSLock()
    private var drafts: [String: AIProviderDraftSnapshot] = [:]

    private init() {}

    func snapshot(for key: String) -> AIProviderDraftSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return drafts[key]
    }

    func save(_ snapshot: AIProviderDraftSnapshot, for key: String) {
        lock.lock()
        drafts[key] = snapshot
        lock.unlock()
    }

    func discard(_ key: String) {
        lock.lock()
        drafts.removeValue(forKey: key)
        lock.unlock()
    }
}
