// Purpose: Feature #177 WI-3 live Foliate registration lifecycle, isolation,
// ordering, and fail-closed current-section contracts.

import Foundation
import Testing

@Suite("Feature #177 WI-3 — live legacy registration")
@MainActor
struct AILegacyDocumentRegistrationTests {
    @Test("updates relocation and stale teardown preserves replacement")
    func liveLifecycle() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("e")
        let token = UUID()
        let session = AIDocumentSessionID(
            fingerprintKey: fp.canonicalKey,
            readerToken: token
        )
        let first = AILegacyDocumentRegistration(
            fingerprint: fp, readerToken: token, registry: registry
        )
        let firstLocator = locator(fp, section: 1, progression: 0.1)
        let firstUpdate = first.updateCurrentSection(
            sectionIndex: 1,
            href: "section-1",
            title: "One",
            locator: firstLocator
        ) { index in
            #expect(index == 1)
            return "first live section"
        }
        await firstUpdate.value

        let firstProvider = try #require(registry.resolve(session: session))
        #expect(try await firstProvider.chunks().first?.text == "first live section")
        #expect(!(try await firstProvider.snapshot()).exactMappingAvailable)

        let replacement = AILegacyDocumentRegistration(
            fingerprint: fp, readerToken: token, registry: registry
        )
        let replacementLocator = locator(fp, section: 2, progression: 0.2)
        let replacementUpdate = replacement.updateCurrentSection(
            sectionIndex: 2,
            href: "section-2",
            title: "Two",
            locator: replacementLocator
        ) { _ in "replacement live section" }
        await replacementUpdate.value

        first.teardown()
        let replacementProvider = try #require(registry.resolve(session: session))
        let snapshot = try await replacementProvider.snapshot()
        #expect(snapshot.currentLocator == replacementLocator)
        #expect(snapshot.currentSectionChunks.first?.text == "replacement live section")

        replacement.teardown()
        #expect(registry.resolve(session: session) == nil)
    }

    @Test("same-book relocation from another reader session is rejected")
    func sameBookForeignReaderTokenIsRejected() {
        let fp = fingerprint("1")
        let expectedToken = UUID()

        #expect(AILegacyDocumentRegistration.matchesSession(
            eventFingerprintKey: fp.canonicalKey,
            eventReaderToken: expectedToken,
            expectedFingerprintKey: fp.canonicalKey,
            expectedReaderToken: expectedToken
        ))
        #expect(!AILegacyDocumentRegistration.matchesSession(
            eventFingerprintKey: fp.canonicalKey,
            eventReaderToken: UUID(),
            expectedFingerprintKey: fp.canonicalKey,
            expectedReaderToken: expectedToken
        ))
    }

    @Test("newest relocation wins when section loads finish out of order")
    func newestRelocationWins() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("f")
        let token = UUID()
        let session = AIDocumentSessionID(
            fingerprintKey: fp.canonicalKey,
            readerToken: token
        )
        let registration = AILegacyDocumentRegistration(
            fingerprint: fp, readerToken: token, registry: registry
        )
        let loader = ControlledLegacySectionLoader()
        var started = loader.started.makeAsyncIterator()
        let oldLocator = locator(fp, section: 1, progression: 0.1)
        let newLocator = locator(fp, section: 2, progression: 0.2)

        let oldUpdate = registration.updateCurrentSection(
            sectionIndex: 1,
            href: "section-1",
            title: "Old",
            locator: oldLocator,
            loadText: { index in await loader.load(sectionIndex: index) }
        )
        #expect(await started.next() == 1)
        let newUpdate = registration.updateCurrentSection(
            sectionIndex: 2,
            href: "section-2",
            title: "New",
            locator: newLocator,
            loadText: { index in await loader.load(sectionIndex: index) }
        )
        #expect(await started.next() == 2)

        await loader.resume(sectionIndex: 2, text: "new section")
        await newUpdate.value
        await loader.resume(sectionIndex: 1, text: "stale old section")
        await oldUpdate.value

        let provider = try #require(registry.resolve(session: session))
        let snapshot = try await provider.snapshot()
        #expect(snapshot.currentLocator == newLocator)
        #expect(snapshot.currentSectionChunks.first?.text == "new section")
    }

    @Test("new section clears stale context before extraction and on failure")
    func newSectionClearsStaleContext() async throws {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("2")
        let token = UUID()
        let session = AIDocumentSessionID(
            fingerprintKey: fp.canonicalKey,
            readerToken: token
        )
        let registration = AILegacyDocumentRegistration(
            fingerprint: fp, readerToken: token, registry: registry
        )
        let initial = registration.updateCurrentSection(
            sectionIndex: 1,
            href: "section-1",
            title: "Old",
            locator: locator(fp, section: 1)
        ) { _ in "old section" }
        await initial.value
        let provider = try #require(registry.resolve(session: session))
        #expect(try await provider.chunks().first?.text == "old section")

        let failed = registration.updateCurrentSection(
            sectionIndex: 2,
            href: "section-2",
            title: "New",
            locator: locator(fp, section: 2)
        ) { _ in nil }

        #expect(try await provider.chunks().isEmpty)
        #expect((try await provider.snapshot()).currentLocator == nil)
        await failed.value
        #expect(try await provider.chunks().isEmpty)
        #expect((try await provider.snapshot()).currentLocator == nil)
    }

    private func fingerprint(_ digit: Character) -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: digit, count: 64),
            fileByteCount: 10,
            format: .azw3
        )
    }

    private func locator(
        _ fingerprint: DocumentFingerprint,
        section: Int,
        progression: Double? = nil
    ) -> Locator {
        Locator.validated(
            bookFingerprint: fingerprint,
            href: "section-\(section)",
            totalProgression: progression,
            cfi: "epubcfi(/6/\(section * 2)!/4/2)"
        )!
    }
}

private actor ControlledLegacySectionLoader {
    nonisolated let started: AsyncStream<Int>
    private let startedContinuation: AsyncStream<Int>.Continuation
    private var pending: [Int: CheckedContinuation<String?, Never>] = [:]

    init() {
        let pair = AsyncStream<Int>.makeStream()
        started = pair.stream
        startedContinuation = pair.continuation
    }

    func load(sectionIndex: Int) async -> String? {
        startedContinuation.yield(sectionIndex)
        return await withCheckedContinuation { continuation in
            pending[sectionIndex] = continuation
        }
    }

    func resume(sectionIndex: Int, text: String?) {
        pending.removeValue(forKey: sectionIndex)?.resume(returning: text)
    }
}
