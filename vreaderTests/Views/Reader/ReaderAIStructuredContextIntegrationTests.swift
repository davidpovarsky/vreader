// Purpose: Feature #177 WI-4 RED integration contracts for exact-session
// coordinator resolution, late attach, and async generation safety.

import Foundation
import Testing
@testable import vreader

@Suite("Feature #177 WI-4 — Reader AI structured integration")
@MainActor
struct ReaderAIStructuredContextIntegrationTests {
    @Test("wrong flattened PDF content cannot affect exact page context")
    func wrongFlattenedPDFContentIsIgnored() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("1", .pdf)
        let token = UUID()
        let page50 = makeChunk(fp, id: "pdf:page:50", index: 50, text: "REAL PAGE 50", page: 50)
        _ = registry.attach(StaticDocumentProvider(fp: fp, snapshot: snapshot(fp, .pdf, page50), chunks: [page50]), for: session(fp, token))
        let coordinator = makeCoordinator(fp, token, registry)
        coordinator.loadedTextContent = "WRONG PAGE 1 FLATTENED TEXT"

        let result = await coordinator.resolveStructuredContext(for: .section)

        #expect(result?.text == "REAL PAGE 50")
        #expect(result?.sourceUnitIDs == ["pdf:page:50"])
    }

    @Test("late exact-session attach is resolved without reopening or fingerprint fallback")
    func lateAttachRecovers() async {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("2", .epub)
        let token = UUID()
        let coordinator = makeCoordinator(fp, token, registry)
        #expect(await coordinator.resolveStructuredContext(for: .section) == nil)

        let resource = makeChunk(fp, id: "epub:b", index: 1, text: "B", href: "b")
        _ = registry.attach(StaticDocumentProvider(fp: fp, snapshot: snapshot(fp, .epub, resource), chunks: [resource]), for: session(fp, token))

        #expect(await coordinator.resolveStructuredContext(for: .section)?.text == "B")
    }

    @Test("two readers of the same book never cross-wire")
    func sameBookSessionsStayIsolated() async {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("3", .epub)
        let tokenA = UUID(), tokenB = UUID()
        let a = makeChunk(fp, id: "epub:a", index: 0, text: "READER A", href: "a")
        let b = makeChunk(fp, id: "epub:b", index: 1, text: "READER B", href: "b")
        _ = registry.attach(StaticDocumentProvider(fp: fp, snapshot: snapshot(fp, .epub, a), chunks: [a]), for: session(fp, tokenA))
        _ = registry.attach(StaticDocumentProvider(fp: fp, snapshot: snapshot(fp, .epub, b), chunks: [b]), for: session(fp, tokenB))

        let resultA = await makeCoordinator(fp, tokenA, registry).resolveStructuredContext(for: .section)
        let resultB = await makeCoordinator(fp, tokenB, registry).resolveStructuredContext(for: .section)

        #expect(resultA?.text == "READER A")
        #expect(resultB?.text == "READER B")
    }

    @Test("missing exact provider fails safely and never reads another session")
    func missingProviderFailsClosed() async {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("4", .pdf)
        let mountedToken = UUID()
        let page = makeChunk(fp, id: "pdf:page:0", index: 0, text: "OTHER READER", page: 0)
        _ = registry.attach(StaticDocumentProvider(fp: fp, snapshot: snapshot(fp, .pdf, page), chunks: [page]), for: session(fp, mountedToken))

        let result = await makeCoordinator(fp, UUID(), registry).resolveStructuredContext(for: .section)

        #expect(result == nil)
    }

    @Test("late old snapshot cannot overwrite a newer refresh")
    func staleSnapshotCannotOverwrite() async {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("5", .pdf)
        let token = UUID()
        let oldChunk = makeChunk(fp, id: "pdf:page:1", index: 1, text: "OLD", page: 1)
        let newChunk = makeChunk(fp, id: "pdf:page:2", index: 2, text: "NEW", page: 2)
        let controlled = ControlledSnapshotProvider(fp: fp, old: snapshot(fp, .pdf, oldChunk), chunks: [oldChunk])
        _ = registry.attach(controlled, for: session(fp, token))
        let coordinator = makeCoordinator(fp, token, registry)

        let oldTask = Task { await coordinator.refreshStructuredContext(for: .section) }
        await controlled.awaitOldSnapshotStarted()
        controlled.replace(snapshot: snapshot(fp, .pdf, newChunk), chunks: [newChunk])
        await coordinator.refreshStructuredContext(for: .section)
        controlled.releaseOldSnapshot()
        await oldTask.value

        #expect(coordinator.cachedStructuredContext(for: .section)?.text == "NEW")
    }

    @Test("provider replaced during an async snapshot cannot return stale context")
    func providerReplacementInvalidatesInFlightResolution() async {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("6", .pdf)
        let token = UUID()
        let oldChunk = makeChunk(fp, id: "pdf:page:1", index: 1, text: "OLD", page: 1)
        let newChunk = makeChunk(fp, id: "pdf:page:2", index: 2, text: "NEW", page: 2)
        let controlled = ControlledSnapshotProvider(
            fp: fp, old: snapshot(fp, .pdf, oldChunk), chunks: [oldChunk]
        )
        _ = registry.attach(controlled, for: session(fp, token))
        let coordinator = makeCoordinator(fp, token, registry)

        let stale = Task { await coordinator.resolveStructuredContext(for: .section) }
        await controlled.awaitOldSnapshotStarted()
        _ = registry.attach(
            StaticDocumentProvider(
                fp: fp, snapshot: snapshot(fp, .pdf, newChunk), chunks: [newChunk]
            ),
            for: session(fp, token)
        )
        controlled.releaseOldSnapshot()

        #expect(await stale.value == nil)
        #expect(await coordinator.resolveStructuredContext(for: .section)?.text == "NEW")
    }

    @Test("scope exit and re-entry cannot resurrect an old whole-book manifest")
    func wholeBookGenerationInvalidatesSuspendedManifest() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("7", .epub)
        let token = UUID()
        let oldChunk = makeChunk(fp, id: "epub:old", index: 0, text: "OLD", href: "old")
        let gated = ControlledManifestProvider(
            fp: fp, snapshot: snapshot(fp, .epub, oldChunk), chunks: [oldChunk]
        )
        _ = registry.attach(gated, for: session(fp, token))
        let coordinator = makeCoordinator(fp, token, registry)
        coordinator.wholeBookReadGeneration = 1

        let stale = Task {
            try await coordinator.currentWholeBookManifest(provider: gated, generation: 1)
        }
        await gated.awaitManifestStarted()
        coordinator.wholeBookReadGeneration = 2 // exit/re-entry supersedes preparation
        gated.releaseManifest()
        #expect(try await stale.value == nil)

        let newChunk = makeChunk(fp, id: "epub:new", index: 1, text: "NEW", href: "new")
        let current = StaticDocumentProvider(
            fp: fp, snapshot: snapshot(fp, .epub, newChunk), chunks: [newChunk]
        )
        _ = registry.attach(current, for: session(fp, token))
        coordinator.wholeBookReadGeneration = 3
        let manifest = try await coordinator.currentWholeBookManifest(
            provider: current, generation: 3
        )
        #expect(manifest?.units.map(\.sourceUnitID) == ["epub:new"])
    }

    @Test("provider replacement invalidates a suspended whole-book manifest")
    func wholeBookProviderReplacementDropsStaleManifest() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("8", .pdf)
        let token = UUID()
        let oldChunk = makeChunk(fp, id: "pdf:page:0", index: 0, text: "OLD", page: 0)
        let gated = ControlledManifestProvider(
            fp: fp, snapshot: snapshot(fp, .pdf, oldChunk), chunks: [oldChunk]
        )
        _ = registry.attach(gated, for: session(fp, token))
        let coordinator = makeCoordinator(fp, token, registry)
        coordinator.wholeBookReadGeneration = 1

        let stale = Task {
            try await coordinator.currentWholeBookManifest(provider: gated, generation: 1)
        }
        await gated.awaitManifestStarted()
        let replacement = StaticDocumentProvider(
            fp: fp, snapshot: snapshot(fp, .pdf, oldChunk), chunks: [oldChunk]
        )
        _ = registry.attach(replacement, for: session(fp, token))
        gated.releaseManifest()

        #expect(try await stale.value == nil)
    }

    private func makeCoordinator(
        _ fp: DocumentFingerprint, _ token: UUID, _ registry: AIDocumentProviderRegistry
    ) -> ReaderAICoordinator {
        ReaderAICoordinator(
            fallbackTitle: "Title", bookFormat: fp.format,
            fingerprintKey: fp.canonicalKey, readerToken: token,
            documentProviderResolver: registry
        )
    }

    private func fingerprint(_ digit: Character, _ format: BookFormat) -> DocumentFingerprint {
        DocumentFingerprint(contentSHA256: String(repeating: digit, count: 64), fileByteCount: 10, format: format)
    }
    private func session(_ fp: DocumentFingerprint, _ token: UUID) -> AIDocumentSessionID {
        AIDocumentSessionID(fingerprintKey: fp.canonicalKey, readerToken: token)
    }
    private func makeChunk(
        _ fp: DocumentFingerprint, id: String, index: Int, text: String,
        page: Int? = nil, href: String? = nil
    ) -> AIDocumentChunk {
        let locator = Locator.validated(bookFingerprint: fp, href: href, page: page)!
        return AIDocumentChunk(
            id: id, bookFingerprintKey: fp.canonicalKey, sourceUnitID: id,
            sourceUnitIndex: index, text: text, locator: locator,
            sourceLabel: nil, chapterTitle: nil, pageIndex: page, href: href,
            localStartUTF16: 0, localEndUTF16: text.utf16.count,
            globalStartUTF16: nil, globalEndUTF16: nil, isOCRDerived: false
        )
    }
    private func snapshot(_ fp: DocumentFingerprint, _ format: BookFormat, _ current: AIDocumentChunk) -> AIDocumentSnapshot {
        AIDocumentSnapshot(
            bookFingerprint: fp, format: format, currentLocator: current.locator,
            currentSourceUnitID: current.sourceUnitID, currentSectionChunks: [current],
            visibleChunks: [current], currentChapterLabel: nil, currentChapterBounds: nil,
            tocSummary: [],
            readSoFarBoundary: AIReadSoFarBoundary(
                locator: current.locator, sourceUnitID: current.sourceUnitID,
                sourceUnitIndex: current.sourceUnitIndex,
                localOffsetUTF16: current.text.utf16.count
            ), exactMappingAvailable: true
        )
    }
}

@MainActor
private final class StaticDocumentProvider: AIDocumentProvider {
    let bookFingerprint: DocumentFingerprint
    let storedSnapshot: AIDocumentSnapshot
    let storedChunks: [AIDocumentChunk]
    init(fp: DocumentFingerprint, snapshot: AIDocumentSnapshot, chunks: [AIDocumentChunk]) {
        bookFingerprint = fp; storedSnapshot = snapshot; storedChunks = chunks
    }
    func snapshot() async throws -> AIDocumentSnapshot { storedSnapshot }
    func chunks() async throws -> [AIDocumentChunk] { storedChunks }
}

@MainActor
private final class ControlledSnapshotProvider: AIDocumentProvider {
    let bookFingerprint: DocumentFingerprint
    private var currentSnapshot: AIDocumentSnapshot
    private let originalSnapshot: AIDocumentSnapshot
    private var currentChunks: [AIDocumentChunk]
    private let startedPair = AsyncStream<Void>.makeStream()
    private var oldContinuation: CheckedContinuation<AIDocumentSnapshot, Never>?
    private var shouldGate = true

    init(fp: DocumentFingerprint, old: AIDocumentSnapshot, chunks: [AIDocumentChunk]) {
        bookFingerprint = fp; currentSnapshot = old; originalSnapshot = old; currentChunks = chunks
    }
    func snapshot() async throws -> AIDocumentSnapshot {
        if shouldGate {
            shouldGate = false
            startedPair.continuation.yield(())
            return await withCheckedContinuation { oldContinuation = $0 }
        }
        return currentSnapshot
    }
    func chunks() async throws -> [AIDocumentChunk] { currentChunks }
    func awaitOldSnapshotStarted() async {
        var iterator = startedPair.stream.makeAsyncIterator(); _ = await iterator.next()
    }
    func replace(snapshot: AIDocumentSnapshot, chunks: [AIDocumentChunk]) {
        currentSnapshot = snapshot; currentChunks = chunks
    }
    func releaseOldSnapshot() { oldContinuation?.resume(returning: originalSnapshot); oldContinuation = nil }
}

@MainActor
private final class ControlledManifestProvider: AIDocumentProvider {
    let bookFingerprint: DocumentFingerprint
    private let storedSnapshot: AIDocumentSnapshot
    private let storedChunks: [AIDocumentChunk]
    private let startedPair = AsyncStream<Void>.makeStream()
    private var manifestContinuation: CheckedContinuation<AIWholeBookSourceManifest, Never>?

    init(fp: DocumentFingerprint, snapshot: AIDocumentSnapshot, chunks: [AIDocumentChunk]) {
        bookFingerprint = fp
        storedSnapshot = snapshot
        storedChunks = chunks
    }

    func snapshot() async throws -> AIDocumentSnapshot { storedSnapshot }
    func chunks() async throws -> [AIDocumentChunk] { storedChunks }
    func wholeBookManifest() async throws -> AIWholeBookSourceManifest {
        startedPair.continuation.yield(())
        return await withCheckedContinuation { manifestContinuation = $0 }
    }
    func awaitManifestStarted() async {
        var iterator = startedPair.stream.makeAsyncIterator()
        _ = await iterator.next()
    }
    func releaseManifest() {
        let manifest = AIWholeBookSourceManifest(
            fingerprintKey: bookFingerprint.canonicalKey,
            enumerationCompleteness: .complete,
            units: storedChunks.map {
                AIWholeBookSourceUnit(
                    sourceUnitID: $0.sourceUnitID,
                    sourceUnitIndex: $0.sourceUnitIndex,
                    availability: .available,
                    chunk: $0
                )
            }
        )
        manifestContinuation?.resume(returning: manifest)
        manifestContinuation = nil
    }
}
