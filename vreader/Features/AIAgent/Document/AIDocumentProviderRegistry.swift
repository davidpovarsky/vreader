// Purpose: Main-actor live-document registry keyed by reader session identity.
// Generation-bearing registrations prevent stale teardown from unregistering a
// newer mount that reused the same reader token.

import Foundation

struct AIDocumentSessionID: Hashable, Sendable {
    let fingerprintKey: String
    let readerToken: UUID
}

struct AIDocumentRegistration: Hashable, Sendable {
    fileprivate let sessionID: AIDocumentSessionID
    fileprivate let generation: UUID
}

@MainActor
protocol AIDocumentProviderResolving: AnyObject {
    func resolve(session: AIDocumentSessionID) -> (any AIDocumentProvider)?
    func resolveUnique(fingerprintKey: String) -> (any AIDocumentProvider)?
}

@MainActor
final class AIDocumentProviderRegistry: AIDocumentProviderResolving {
    static let shared = AIDocumentProviderRegistry()

    private struct Entry {
        let generation: UUID
        let provider: any AIDocumentProvider
    }

    private var entries: [AIDocumentSessionID: Entry] = [:]

    @discardableResult
    func attach(
        _ provider: any AIDocumentProvider,
        for session: AIDocumentSessionID
    ) -> AIDocumentRegistration {
        precondition(
            provider.bookFingerprint.canonicalKey == session.fingerprintKey,
            "A document provider cannot register under another book fingerprint"
        )
        let generation = UUID()
        entries[session] = Entry(generation: generation, provider: provider)
        return AIDocumentRegistration(sessionID: session, generation: generation)
    }

    func detach(_ registration: AIDocumentRegistration) {
        guard entries[registration.sessionID]?.generation == registration.generation else {
            return
        }
        entries.removeValue(forKey: registration.sessionID)
    }

    func resolve(session: AIDocumentSessionID) -> (any AIDocumentProvider)? {
        entries[session]?.provider
    }

    /// Fingerprint-only fallback is deliberately fail-closed when two mounted
    /// readers show the same book. WI-4 can always resolve by exact session.
    func resolveUnique(fingerprintKey: String) -> (any AIDocumentProvider)? {
        let matches = entries.compactMap { key, entry in
            key.fingerprintKey == fingerprintKey ? entry.provider : nil
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }
}
