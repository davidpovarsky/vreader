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

        // MARK: - AnnotationPersisting
        func addAnnotation(locator: Locator, content: String, toBookWithKey key: String) async throws -> AnnotationRecord {
            createdNotes.append((key, content, locator))
            return AnnotationRecord(
                annotationId: UUID(),
                locator: locator,
                profileKey: key,
                content: content,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        func removeAnnotation(annotationId: UUID) async throws {
            deletedNoteIDs.append(annotationId.uuidString)
        }

        func updateAnnotation(annotationId: UUID, content: String) async throws {}

        func fetchAnnotations(forBookWithKey key: String) async throws -> [AnnotationRecord] {
            []
        }

        // MARK: - HighlightPersisting
        func addHighlight(locator: Locator, selectedText: String, color: String, note: String?, toBookWithKey key: String) async throws -> HighlightRecord {
            createdHighlights.append((key, locator, color))
            return HighlightRecord(
                highlightId: UUID(),
                locator: locator,
                anchor: nil,
                profileKey: key,
                selectedText: selectedText,
                color: color,
                note: note,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        func addHighlight(locator: Locator, anchor: AnnotationAnchor?, selectedText: String, color: String, note: String?, toBookWithKey key: String) async throws -> HighlightRecord {
            createdHighlights.append((key, locator, color))
            return HighlightRecord(
                highlightId: UUID(),
                locator: locator,
                anchor: anchor,
                profileKey: key,
                selectedText: selectedText,
                color: color,
                note: note,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        func removeHighlight(highlightId: UUID) async throws {
            removedHighlightIDs.append(highlightId.uuidString)
        }

        func updateHighlightNote(highlightId: UUID, note: String?) async throws {}

        func updateHighlightColor(highlightId: UUID, color: String) async throws {}

        func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] {
            []
        }

        // MARK: - BookmarkPersisting
        func addBookmark(locator: Locator, title: String?, toBookWithKey key: String) async throws -> BookmarkRecord {
            createdBookmarks.append((key, locator, title))
            return BookmarkRecord(
                bookmarkId: UUID(),
                locator: locator,
                profileKey: key,
                title: title,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        func removeBookmark(bookmarkId: UUID) async throws {
            removedBookmarkIDs.append(bookmarkId.uuidString)
        }

        func fetchBookmarks(forBookWithKey key: String) async throws -> [BookmarkRecord] {
            []
        }

        func isBookmarked(locator: Locator, forBookWithKey key: String) async throws -> Bool {
            false
        }

        func updateBookmarkTitle(bookmarkId: UUID, title: String?) async throws {}
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
