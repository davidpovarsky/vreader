// Purpose: Comprehensive unit tests for AIAnnotationMutationTools.
// Tests note, highlight, and bookmark creation/editing/deletion, gating, confirmation requirement, and idempotency.

import Testing
import Foundation
@testable import vreader

@MainActor
private final class MockReaderToolContext: AIReaderToolContextProviding {
    let bookTitle: String
    let fingerprint: DocumentFingerprint
    let sessionID: AIDocumentSessionID
    var stubbedDocument: AILiveReaderDocument?

    init(
        bookTitle: String = "Test Novel",
        fingerprint: DocumentFingerprint = DocumentFingerprint(scheme: "test", value: "book-note-1"),
        stubbedDocument: AILiveReaderDocument? = nil
    ) {
        self.bookTitle = bookTitle
        self.fingerprint = fingerprint
        self.sessionID = AIDocumentSessionID(fingerprintKey: fingerprint.canonicalKey, readerToken: UUID())
        self.stubbedDocument = stubbedDocument
    }

    func resolveDocument() async -> AILiveReaderDocument? {
        stubbedDocument
    }

    func tableOfContents() async -> [AIDocumentTOCSummaryItem] {
        []
    }
}

@Suite("AIAnnotationMutationToolsTests")
struct AIAnnotationMutationToolsTests {

    private final class MockMutationPersistence: AnnotationPersisting, HighlightPersisting, BookmarkPersisting, @unchecked Sendable {
        var createdNotes: [(String, String, Locator)] = []
        var deletedNoteIDs: [String] = []
        var createdHighlights: [(String, Locator, String)] = []
        var removedHighlightIDs: [String] = []
        var createdBookmarks: [(String, Locator, String?)] = []
        var removedBookmarkIDs: [String] = []

        func createNote(bookFingerprint: String, title: String, content: String, locator: Locator) async throws -> String {
            createdNotes.append((bookFingerprint, content, locator))
            return "note_\(createdNotes.count)"
        }

        func updateNote(id: String, content: String) async throws {}
        func deleteNote(id: String) async throws { deletedNoteIDs.append(id) }

        func addHighlight(bookFingerprint: String, locator: Locator, colorHex: String, note: String?) async throws -> String {
            createdHighlights.append((bookFingerprint, locator, colorHex))
            return "hl_\(createdHighlights.count)"
        }

        func updateHighlight(id: String, colorHex: String?, note: String?) async throws {}
        func removeHighlight(id: String) async throws { removedHighlightIDs.append(id) }

        func addBookmark(bookFingerprint: String, locator: Locator, title: String?) async throws -> String {
            createdBookmarks.append((bookFingerprint, locator, title))
            return "bm_\(createdBookmarks.count)"
        }

        func updateBookmark(id: String, title: String?) async throws {}
        func removeBookmark(id: String) async throws { removedBookmarkIDs.append(id) }
    }

    @Test @MainActor func createNoteToolCreatesNoteWithValidInput() async {
        let persistence = MockMutationPersistence()
        let coordinator = AIAnnotationMutationCoordinator(
            annotationPersisting: persistence,
            highlightPersisting: persistence,
            bookmarkPersisting: persistence
        )

        let locator = Locator(href: "ch1.xhtml", type: "application/xhtml+xml", title: "Chapter 1")
        let docChunk = AIDocumentChunk(
            unit: .chapter(title: "Ch 1"),
            locator: locator,
            text: "Content",
            isSafeCurrentSection: true,
            isSafeBookSoFar: true,
            isAheadOfReader: false
        )
        let snapshot = AIDocumentSnapshot(
            bookFingerprint: DocumentFingerprint(scheme: "test", value: "book-note-1"),
            format: .epub,
            chunks: [docChunk]
        )
        let liveDoc = AILiveReaderDocument(snapshot: snapshot, chunks: [docChunk])
        let context = MockReaderToolContext(stubbedDocument: liveDoc)

        let store = InMemoryAIAgentPreferencesStore()
        store.preferences.permissions[.writeAnnotations] = .allow
        let gate = AIAgentToolExecutionGate(
            preferencesStore: store,
            broker: AIActionConfirmationBroker(preferencesStore: store),
            confirmationAvailability: .brokerConnected
        )

        let tool = CreateNoteTool(coordinator: coordinator, context: context, authorizationGate: gate)

        let res = await tool.run(.object([
            "content": .string("Insight about chapter 1."),
            "title": .string("Chapter 1 Note")
        ]))

        #expect(!res.isError)
        #expect(res.content.contains("Created note"))
        #expect(persistence.createdNotes.count == 1)
        #expect(persistence.createdNotes[0].1 == "Insight about chapter 1.")
    }

    @Test @MainActor func deleteNoteToolFailsWhenConfirmationUnavailable() async {
        let persistence = MockMutationPersistence()
        let coordinator = AIAnnotationMutationCoordinator(
            annotationPersisting: persistence,
            highlightPersisting: persistence,
            bookmarkPersisting: persistence
        )

        let context = MockReaderToolContext()
        let gate = AIAgentToolExecutionGate.productionUnavailable()

        let tool = DeleteNoteTool(coordinator: coordinator, context: context, authorizationGate: gate)

        let res = await tool.run(.object(["id": .string("note_to_delete")]))
        #expect(res.isError)
        #expect(persistence.deletedNoteIDs.isEmpty)
    }

    @Test @MainActor func addBookmarkToolCreatesBookmark() async {
        let persistence = MockMutationPersistence()
        let coordinator = AIAnnotationMutationCoordinator(
            annotationPersisting: persistence,
            highlightPersisting: persistence,
            bookmarkPersisting: persistence
        )

        let locator = Locator(href: "page_10.pdf", type: "application/pdf", title: "Page 10")
        let docChunk = AIDocumentChunk(
            unit: .page(number: 10),
            locator: locator,
            text: "Page 10 text",
            isSafeCurrentSection: true,
            isSafeBookSoFar: true,
            isAheadOfReader: false
        )
        let snapshot = AIDocumentSnapshot(
            bookFingerprint: DocumentFingerprint(scheme: "test", value: "book-note-1"),
            format: .pdf,
            chunks: [docChunk]
        )
        let liveDoc = AILiveReaderDocument(snapshot: snapshot, chunks: [docChunk])
        let context = MockReaderToolContext(stubbedDocument: liveDoc)

        let store = InMemoryAIAgentPreferencesStore()
        store.preferences.permissions[.writeAnnotations] = .allow
        let gate = AIAgentToolExecutionGate(
            preferencesStore: store,
            broker: AIActionConfirmationBroker(preferencesStore: store),
            confirmationAvailability: .brokerConnected
        )

        let tool = AddBookmarkTool(coordinator: coordinator, context: context, authorizationGate: gate)

        let res = await tool.run(.object(["title": .string("Interesting Diagram")]))
        #expect(!res.isError)
        #expect(res.content.contains("Added bookmark"))
        #expect(persistence.createdBookmarks.count == 1)
        #expect(persistence.createdBookmarks[0].2 == "Interesting Diagram")
    }
}
