// Purpose: Bug #249 / GH #1080 — pins the delete affordance the committed
// design (`vreader-notes-delete.jsx`) adds to `HighlightsSheet`'s cards.
//
// The feature #62 WI-5 migration from `AnnotationListView` (List +
// `.onDelete`) to `HighlightsSheet` (`ScrollView` + `LazyVStack`) dropped
// swipe-to-delete. The committed design restores deletion via a trailing ⋯
// menu (Edit · Copy · Delete) + an inline confirm strip + a left-swipe path.
// These tests guard the DATA effect — confirming a delete actually removes
// the record from both the in-memory stream AND `PersistenceActor` storage,
// for both card kinds — plus the menu/confirm/copy contract.
//
// @coordinates-with: HighlightsSheet.swift, HighlightsSheet+Delete.swift,
//   NotesActionMenu.swift, NotesRowState.swift, HighlightAnnotationCard.swift

import Testing
import SwiftUI
import SwiftData
import UIKit
@testable import vreader

@Suite("Bug #249 — HighlightsSheet delete affordance")
@MainActor
struct HighlightsSheetDeleteTests {

    // MARK: - Fixtures

    private func inMemoryContainer() -> ModelContainer {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    /// Seeds a book with N highlights (first carries a note) and one
    /// standalone note; returns the key + container + the seeded ids.
    private func seed() async throws -> (key: String, container: ModelContainer,
                                         highlightIds: [UUID], annotationId: UUID) {
        let container = inMemoryContainer()
        let persistence = PersistenceActor(modelContainer: container)
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let fp = DocumentFingerprint(canonicalKey: key)!
        let h1 = try await persistence.addHighlight(
            locator: LocatorFactory.epub(fingerprint: fp, href: "ch0.xhtml", progression: 0.1)!,
            selectedText: "passage one", color: "yellow", note: nil,
            toBookWithKey: key
        )
        let h2 = try await persistence.addHighlight(
            locator: LocatorFactory.epub(fingerprint: fp, href: "ch1.xhtml", progression: 0.2)!,
            selectedText: "passage two", color: "pink", note: "an annotated highlight",
            toBookWithKey: key
        )
        let s1 = try await persistence.addAnnotation(
            locator: LocatorFactory.epub(fingerprint: fp, href: "ch2.xhtml", progression: 0.3)!,
            content: "a standalone note",
            toBookWithKey: key
        )
        return (key, container, [h1.highlightId, h2.highlightId], s1.annotationId)
    }

    private func makeSheet(key: String, container: ModelContainer) -> HighlightsSheet {
        HighlightsSheet(
            bookFingerprintKey: key, modelContainer: container,
            theme: .paper, initialFilter: .all,
            onNavigate: { _ in }, onDismiss: {}
        )
    }

    // MARK: - Delete effect — highlight

    @Test("Deleting a highlight removes it from persistence and the stream")
    func deleteHighlightRemovesFromStoreAndStream() async throws {
        let s = try await seed()
        let sheet = makeSheet(key: s.key, container: s.container)
        let target = s.highlightIds[0]

        let remaining = await sheet.deleteHighlightForTesting(highlightId: target)

        // The deleted highlight is gone from the returned stream.
        #expect(!remaining.contains { $0.id == target })
        // And gone from persistence — the definitive check.
        let persistence = PersistenceActor(modelContainer: s.container)
        let stored = try await persistence.fetchHighlights(forBookWithKey: s.key)
        #expect(!stored.contains { $0.highlightId == target })
        #expect(stored.count == 1)   // the other highlight survives
    }

    // MARK: - Delete effect — standalone note

    @Test("Deleting a standalone note removes it from persistence and the stream")
    func deleteAnnotationRemovesFromStoreAndStream() async throws {
        let s = try await seed()
        let sheet = makeSheet(key: s.key, container: s.container)

        let remaining = await sheet.deleteAnnotationForTesting(annotationId: s.annotationId)

        #expect(!remaining.contains { $0.id == s.annotationId })
        let persistence = PersistenceActor(modelContainer: s.container)
        let stored = try await persistence.fetchAnnotations(forBookWithKey: s.key)
        #expect(!stored.contains { $0.annotationId == s.annotationId })
        #expect(stored.isEmpty)
    }

    // MARK: - Confirm gates the delete

    @Test("The confirm strip phase precedes the delete — menu → confirm → deleting")
    func confirmGatesDelete() {
        let rowId = UUID()
        // Tapping Delete in the menu moves to confirm (NOT straight to delete).
        let confirming = NotesRowState.resting.openingMenu(for: rowId).confirmingDelete(for: rowId)
        #expect(confirming.phase(for: rowId) == .confirming)
        // Only confirming → deleting commits.
        let deleting = confirming.deleting(rowId)
        #expect(deleting.phase(for: rowId) == .deleting)
        // Cancel from confirm returns to rest WITHOUT a delete.
        #expect(confirming.dismissed() == .resting)
    }

    // MARK: - Menu exposes Edit / Copy / Delete

    @Test("The action menu builds with all three items for both kinds")
    func actionMenuBuildsBothKinds() {
        for kind in [NotesActionKind.highlight, .standalone] {
            let menu = NotesActionMenu(
                theme: .paper, kind: kind,
                onEdit: {}, onCopy: {}, onDelete: {}
            )
            _ = menu.body
        }
    }

    // MARK: - Copy writes the pasteboard

    @Test("Copy on a highlight writes the quote to the pasteboard")
    func copyHighlightWritesPasteboard() async throws {
        let s = try await seed()
        let sheet = makeSheet(key: s.key, container: s.container)
        UIPasteboard.general.string = ""
        await sheet.copyHighlightForTesting(highlightId: s.highlightIds[0])
        // "passage one" was the first seeded highlight's text.
        #expect(UIPasteboard.general.string == "passage one")
    }

    @Test("Copy on a standalone note writes the note body to the pasteboard")
    func copyAnnotationWritesPasteboard() async throws {
        let s = try await seed()
        let sheet = makeSheet(key: s.key, container: s.container)
        UIPasteboard.general.string = ""
        await sheet.copyAnnotationForTesting(annotationId: s.annotationId)
        #expect(UIPasteboard.general.string == "a standalone note")
    }

    // MARK: - Async-race guard (Codex Gate-4 High finding)

    @Test("A stale in-flight delete on row A must not clobber row B's interaction")
    func staleDeleteDoesNotClobberOtherRow() {
        // `confirmDelete` guards its post-await transition on
        // `activeRowId == id && phase == .deleting`. Model the race at the
        // state level: row A is deleting, the user opens row B's menu before
        // A's await returns, so when A's completion fires the guard must
        // recognise A is no longer the active deleting row.
        let rowA = UUID(), rowB = UUID()
        let deletingA = NotesRowState.resting.deleting(rowA)
        let movedToB = deletingA.openingMenu(for: rowB)
        // The guard the production code uses:
        let guardHoldsForA = (movedToB.activeRowId == rowA && movedToB.phase == .deleting)
        #expect(guardHoldsForA == false)        // A's completion is suppressed
        #expect(movedToB.activeRowId == rowB)   // B's menu survives intact
        #expect(movedToB.phase == .menuOpen)
    }

    @Test("When the deleting row is still active, its completion is allowed")
    func liveDeleteCompletionAllowed() {
        let rowA = UUID()
        let deletingA = NotesRowState.resting.deleting(rowA)
        let guardHolds = (deletingA.activeRowId == rowA && deletingA.phase == .deleting)
        #expect(guardHolds)   // no other interaction supervened → completion applies
    }

    // MARK: - Builds with the affordance on every theme + card kind

    @Test("The sheet body builds with the delete affordance for every theme")
    func bodyBuildsWithAffordanceEveryTheme() async throws {
        let s = try await seed()
        for theme in ReaderThemeV2.allCases {
            let sheet = HighlightsSheet(
                bookFingerprintKey: s.key, modelContainer: s.container,
                theme: theme, initialFilter: .all,
                onNavigate: { _ in }, onDismiss: {}
            )
            _ = sheet.body
        }
    }

    // MARK: - Edit handoff (navigate-to-passage)

    @Test("Edit on a highlight navigates to its locator and dismisses the sheet")
    func editHighlightNavigatesAndDismisses() async throws {
        let s = try await seed()
        nonisolated(unsafe) var navigated: Locator?
        nonisolated(unsafe) var dismissed = false
        // Build the VMs through a sheet wired with capturing callbacks, then
        // drive `edit(_:)` on a highlight stream item.
        let (hVM, _) = await loadVMs(key: s.key, container: s.container)
        let record = hVM.highlights.first { $0.highlightId == s.highlightIds[0] }!
        let sheet = HighlightsSheet(
            bookFingerprintKey: s.key, modelContainer: s.container,
            theme: .paper, initialFilter: .all,
            onNavigate: { navigated = $0 }, onDismiss: { dismissed = true }
        )
        sheet.edit(.highlight(record))
        #expect(navigated == record.locator)
        #expect(dismissed)
    }

    private func loadVMs(key: String, container: ModelContainer)
        async -> (HighlightListViewModel, AnnotationListViewModel) {
        let persistence = PersistenceActor(modelContainer: container)
        let hVM = HighlightListViewModel(
            bookFingerprintKey: key, store: persistence, totalTextLengthUTF16: nil
        )
        let aVM = AnnotationListViewModel(bookFingerprintKey: key, store: persistence)
        await hVM.loadHighlights()
        await aVM.loadAnnotations()
        return (hVM, aVM)
    }
}
