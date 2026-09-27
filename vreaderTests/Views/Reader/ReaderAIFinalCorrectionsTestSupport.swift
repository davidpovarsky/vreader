// Purpose: Deterministic document-provider fixtures for WI-4 final regressions.

import Foundation
@testable import vreader

@MainActor
final class StaticFinalCorrectionsProvider: AIDocumentProvider {
    let bookFingerprint: DocumentFingerprint
    private let storedSnapshot: AIDocumentSnapshot
    private let storedChunks: [AIDocumentChunk]

    init(
        fp: DocumentFingerprint,
        snapshot: AIDocumentSnapshot,
        chunks: [AIDocumentChunk]
    ) {
        bookFingerprint = fp
        storedSnapshot = snapshot
        storedChunks = chunks
    }

    func snapshot() async throws -> AIDocumentSnapshot { storedSnapshot }
    func chunks() async throws -> [AIDocumentChunk] { storedChunks }
}

@MainActor
final class GatedFinalCorrectionsProvider: AIDocumentProvider {
    let bookFingerprint: DocumentFingerprint
    private let storedSnapshot: AIDocumentSnapshot
    private let storedChunks: [AIDocumentChunk]
    private let started = AsyncStream<Void>.makeStream()
    private var snapshotContinuation: CheckedContinuation<AIDocumentSnapshot, Never>?

    init(
        fp: DocumentFingerprint,
        snapshot: AIDocumentSnapshot,
        chunks: [AIDocumentChunk]
    ) {
        bookFingerprint = fp
        storedSnapshot = snapshot
        storedChunks = chunks
    }

    func snapshot() async throws -> AIDocumentSnapshot {
        started.continuation.yield(())
        return await withCheckedContinuation { snapshotContinuation = $0 }
    }

    func chunks() async throws -> [AIDocumentChunk] { storedChunks }

    func awaitSnapshotStarted() async {
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func releaseSnapshot() {
        snapshotContinuation?.resume(returning: storedSnapshot)
        snapshotContinuation = nil
    }
}
