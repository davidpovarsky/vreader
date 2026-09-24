// Purpose: Feature #177 WI-3 RED contracts for registry lifetime, cancellation,
// and bounded legacy AZW3/MOBI mapping precision.

import Foundation
import Testing

@Suite("Feature #177 WI-3 — registry, cancellation, and legacy mapping")
@MainActor
struct AIRegistryLegacyAndCancellationTests {
    private func fingerprint(_ digit: Character, format: BookFormat = .txt) -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: digit, count: 64),
            fileByteCount: 10,
            format: format
        )
    }

    @Test("live registry attach resolves exact session and detach removes it")
    func registryAttachResolveDetach() {
        let registry = AIDocumentProviderRegistry()
        let fp = fingerprint("5")
        let session = AIDocumentSessionID(
            fingerprintKey: fp.canonicalKey,
            readerToken: UUID()
        )
        let provider = AITXTDocumentProvider(
            fingerprint: fp,
            text: "reader one",
            currentLocator: Locator.validated(bookFingerprint: fp, charOffsetUTF16: 0)!
        )

        let registration = registry.attach(provider, for: session)
        #expect(registry.resolve(session: session) === provider)

        registry.detach(registration)
        #expect(registry.resolve(session: session) == nil)
        #expect(registry.resolveUnique(fingerprintKey: fp.canonicalKey) == nil)
    }

    @Test("two readers cannot cross-wire and stale teardown cannot remove replacement")
    func readersStayIsolated() {
        let registry = AIDocumentProviderRegistry()
        let fpA = fingerprint("6")
        let fpB = fingerprint("7")
        let tokenA = UUID()
        let tokenB = UUID()
        let sessionA = AIDocumentSessionID(fingerprintKey: fpA.canonicalKey, readerToken: tokenA)
        let secondSessionA = AIDocumentSessionID(
            fingerprintKey: fpA.canonicalKey,
            readerToken: UUID()
        )
        let sessionB = AIDocumentSessionID(fingerprintKey: fpB.canonicalKey, readerToken: tokenB)
        let firstA = textProvider(fp: fpA, text: "old A")
        let replacementA = textProvider(fp: fpA, text: "new A")
        let secondReaderA = textProvider(fp: fpA, text: "second reader A")
        let providerB = textProvider(fp: fpB, text: "book B")

        let staleRegistration = registry.attach(firstA, for: sessionA)
        let currentRegistration = registry.attach(replacementA, for: sessionA)
        _ = registry.attach(secondReaderA, for: secondSessionA)
        _ = registry.attach(providerB, for: sessionB)
        registry.detach(staleRegistration)

        #expect(registry.resolve(session: sessionA) === replacementA)
        #expect(registry.resolve(session: secondSessionA) === secondReaderA)
        #expect(registry.resolve(session: sessionB) === providerB)
        #expect(registry.resolveUnique(fingerprintKey: fpA.canonicalKey) == nil)

        registry.detach(currentRegistration)
        #expect(registry.resolve(session: sessionA) == nil)
        #expect(registry.resolveUnique(fingerprintKey: fpA.canonicalKey) === secondReaderA)
        #expect(registry.resolve(session: sessionB) === providerB)
    }

    @Test("provider cancellation propagates during enumeration")
    func cancellationPropagates() async {
        let fp = fingerprint("8", format: .pdf)
        let facade = CancellationPDFValueFacade()
        let provider = AIPDFDocumentProvider(fingerprint: fp, facade: facade)
        var iterator = facade.started.makeAsyncIterator()
        let task = Task { try await provider.chunks() }

        _ = await iterator.next()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Intended cancellation path.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    @Test("legacy adapter is bounded to current section and reports approximate precision")
    func legacyAdapterIsHonest() async throws {
        let fp = fingerprint("9", format: .azw3)
        let locator = Locator.validated(
            bookFingerprint: fp,
            href: "section-12",
            progression: 0.42,
            totalProgression: 0.42,
            cfi: "epubcfi(/6/24!/4/2)"
        )!
        let provider = AILegacyDocumentProvider(
            fingerprint: fp,
            currentSection: AILegacyDocumentSection(
                sectionIndex: 12,
                href: "section-12",
                title: "Current section",
                text: "bounded text",
                locator: locator,
                mappingPrecision: .approximate
            )
        )

        let chunks = try await provider.chunks()
        let snapshot = try await provider.snapshot()

        #expect(chunks.count == 1)
        #expect(chunks[0].sourceUnitID == "foliate:section:12")
        #expect(chunks[0].locator.cfi == locator.cfi)
        #expect(chunks[0].bookFingerprintKey == fp.canonicalKey)
        #expect(!snapshot.exactMappingAvailable)
        #expect(snapshot.currentSectionChunks == chunks)
    }

    @Test("legacy adapter reports exact only when the native relocation is exact")
    func legacyExactPrecisionIsPreserved() async throws {
        let fp = fingerprint("b", format: .azw3)
        let locator = Locator.validated(
            bookFingerprint: fp,
            href: "section-3",
            progression: 0.2,
            cfi: "epubcfi(/6/6!/4/2)"
        )!
        let provider = AILegacyDocumentProvider(
            fingerprint: fp,
            currentSection: AILegacyDocumentSection(
                sectionIndex: 3,
                href: "section-3",
                title: nil,
                text: "exact native section",
                locator: locator,
                mappingPrecision: .exact
            )
        )

        let snapshot = try await provider.snapshot()

        #expect(snapshot.exactMappingAvailable)
        #expect(snapshot.currentSourceUnitID == "foliate:section:3")
        #expect(snapshot.currentLocator == locator)
    }

    @Test("legacy adapter fails closed when no current section exists")
    func legacyMissingSectionFailsClosed() async throws {
        let fp = fingerprint("a", format: .azw3)
        let provider = AILegacyDocumentProvider(fingerprint: fp, currentSection: nil)

        #expect(try await provider.chunks().isEmpty)
        #expect(!(try await provider.snapshot()).exactMappingAvailable)
    }

    private func textProvider(fp: DocumentFingerprint, text: String) -> AITXTDocumentProvider {
        AITXTDocumentProvider(
            fingerprint: fp,
            text: text,
            currentLocator: Locator.validated(bookFingerprint: fp, charOffsetUTF16: 0)!
        )
    }
}

@MainActor
private final class CancellationPDFValueFacade: AIPDFDocumentFacading {
    let pageCount = 2
    let currentPageIndex: Int? = 0
    let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation

    init() {
        let pair = AsyncStream<Void>.makeStream()
        started = pair.stream
        startedContinuation = pair.continuation
    }

    func text(forPage index: Int) async throws -> String {
        startedContinuation.yield()
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return "page \(index)"
    }
}
