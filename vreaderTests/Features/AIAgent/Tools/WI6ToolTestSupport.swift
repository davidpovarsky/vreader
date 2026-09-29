// Purpose: Shared deterministic fixtures for Feature #177 WI-6 tool tests.

import Foundation
@testable import vreader

actor WI6PreferencesStore: AIAgentPreferencesStoring {
    private var value: AIAgentPreferences

    init(_ value: AIAgentPreferences) { self.value = value }

    func load() -> AIAgentPreferences { value }

    func setDecision(
        _ decision: AIToolPermissionDecision,
        for category: AIToolPermissionCategory
    ) {
        value.setDecision(decision, for: category)
    }

    func setReadAheadMode(_ mode: AIReadAheadMode) {
        value.setReadAheadMode(mode)
    }
}

actor WI6CompletionProbe {
    private(set) var completed = false

    func markCompleted() {
        completed = true
    }
}

enum WI6Fixtures {
    static func fingerprint(_ character: Character = "a", format: BookFormat = .txt) -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: String(character), count: 64),
            fileByteCount: 4_096,
            format: format
        )
    }

    static func preferences(
        _ decisions: [AIToolPermissionCategory: AIToolPermissionDecision],
        readAhead: AIReadAheadMode = .neverReadAhead
    ) -> AIAgentPreferences {
        AIAgentPreferences(permissionDecisions: decisions, readAheadMode: readAhead)
    }

    static func gate(
        _ decisions: [AIToolPermissionCategory: AIToolPermissionDecision],
        readAhead: AIReadAheadMode = .neverReadAhead,
        broker: AIActionConfirmationBroker? = nil,
        confirmationAvailable: Bool = true
    ) -> AIAgentToolExecutionGate {
        let store = WI6PreferencesStore(preferences(decisions, readAhead: readAhead))
        return AIAgentToolExecutionGate(
            preferencesStore: store,
            broker: broker ?? AIActionConfirmationBroker(preferencesStore: store),
            confirmationAvailability: confirmationAvailable ? .brokerConnected : .unavailable
        )
    }

    static func locator(
        fingerprint: DocumentFingerprint,
        page: Int? = nil,
        href: String? = nil,
        offset: Int? = nil,
        range: Range<Int>? = nil
    ) -> Locator {
        Locator.validated(
            bookFingerprint: fingerprint,
            href: href,
            page: page,
            charOffsetUTF16: offset,
            charRangeStartUTF16: range?.lowerBound,
            charRangeEndUTF16: range?.upperBound
        )!
    }

    static func chunk(
        fingerprint: DocumentFingerprint,
        id: String,
        index: Int?,
        text: String,
        page: Int? = nil,
        href: String? = nil,
        local: Range<Int>? = nil,
        global: Range<Int>? = nil
    ) -> AIDocumentChunk {
        let locator = self.locator(
            fingerprint: fingerprint,
            page: page,
            href: href,
            offset: global?.lowerBound,
            range: global
        )
        return AIDocumentChunk(
            id: id,
            bookFingerprintKey: fingerprint.canonicalKey,
            sourceUnitID: id,
            sourceUnitIndex: index,
            text: text,
            locator: locator,
            sourceLabel: page.map { "Page \($0 + 1)" },
            chapterTitle: nil,
            pageIndex: page,
            href: href,
            localStartUTF16: local?.lowerBound,
            localEndUTF16: local?.upperBound,
            globalStartUTF16: global?.lowerBound,
            globalEndUTF16: global?.upperBound,
            isOCRDerived: false
        )
    }

    static func snapshot(
        fingerprint: DocumentFingerprint,
        current: AIDocumentChunk,
        localBoundary: Int?,
        globalBoundary: Int? = nil,
        chapterBounds: ChapterBounds? = nil,
        toc: [AIDocumentTOCSummaryItem] = []
    ) -> AIDocumentSnapshot {
        AIDocumentSnapshot(
            bookFingerprint: fingerprint,
            format: fingerprint.format,
            currentLocator: current.locator,
            currentSourceUnitID: current.sourceUnitID,
            currentSectionChunks: [current],
            visibleChunks: [current],
            currentChapterLabel: current.chapterTitle,
            currentChapterBounds: chapterBounds,
            tocSummary: toc,
            readSoFarBoundary: AIReadSoFarBoundary(
                locator: current.locator,
                sourceUnitID: current.sourceUnitID,
                sourceUnitIndex: current.sourceUnitIndex,
                localOffsetUTF16: localBoundary,
                globalOffsetUTF16: globalBoundary
            ),
            exactMappingAvailable: true
        )
    }
}

@MainActor
final class WI6DocumentProvider: AIDocumentProvider {
    let bookFingerprint: DocumentFingerprint
    var storedChunks: [AIDocumentChunk]
    var storedSnapshot: AIDocumentSnapshot

    init(
        fingerprint: DocumentFingerprint,
        chunks: [AIDocumentChunk],
        snapshot: AIDocumentSnapshot
    ) {
        bookFingerprint = fingerprint
        storedChunks = chunks
        storedSnapshot = snapshot
    }

    func chunks() async throws -> [AIDocumentChunk] { storedChunks }
    func snapshot() async throws -> AIDocumentSnapshot { storedSnapshot }
}

func resolveNextWI6Confirmation(
    on broker: AIActionConfirmationBroker,
    with response: AIActionConfirmationResponse
) -> Task<Void, Never> {
    Task {
        let stream = await broker.pendingRequestUpdates()
        for await requests in stream {
            if let request = requests.first {
                _ = await broker.resolve(request.id, with: response)
                return
            }
        }
    }
}
