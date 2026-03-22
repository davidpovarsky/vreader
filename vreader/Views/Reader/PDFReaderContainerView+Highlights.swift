// Purpose: Highlight action handling and note input sheet for
// PDFReaderContainerView. Pure code extraction — no logic changes.
//
// @coordinates-with: PDFReaderContainerView.swift, PDFAnnotationBridge.swift,
//   PDFHighlightRenderer.swift, HighlightCoordinator.swift, HighlightPersisting.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData

extension PDFReaderContainerView {

    // MARK: - Highlight Actions

    /// Phase R4b: delegates to coordinator (persists -> renderer.apply() with real ID).
    func handleHighlightAction(
        event: ReaderSelectionEvent,
        container: ModelContainer
    ) {
        let locator = viewModel.makeCurrentLocator()

        if let coordinator = highlightCoordinator {
            Task {
                await coordinator.create(
                    locator: locator,
                    anchor: event.anchor,
                    selectedText: event.selectedText,
                    color: "yellow"
                )
            }
        } else {
            // Fallback: direct persistence + bridge-driven create if coordinator not ready
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                try? await persistence.addHighlight(
                    locator: locator, anchor: event.anchor,
                    selectedText: event.selectedText, color: "yellow",
                    note: nil, toBookWithKey: viewModel.bookFingerprintKey
                )
            }
            pendingHighlightPayload = PDFHighlightNotificationPayload(
                anchor: event.anchor, color: "yellow"
            )
            pendingHighlightId += 1
        }
        pendingSelectionEvent = nil
    }

    // MARK: - Note Input Sheet

    @ViewBuilder
    var pdfNoteInputSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let event = pendingSelectionEvent {
                    Text(event.selectedText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                TextEditor(text: $noteText)
                    .frame(minHeight: 100)
                    .padding(.horizontal)
                    .accessibilityIdentifier("pdfNoteTextEditor")
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showNoteSheet = false
                        pendingSelectionEvent = nil
                    }
                    .accessibilityIdentifier("pdfNoteCancelButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let event = pendingSelectionEvent,
                              let container = modelContainer else {
                            showNoteSheet = false
                            return
                        }
                        handleHighlightWithNote(
                            event: event,
                            container: container,
                            note: noteText.isEmpty ? nil : noteText
                        )
                        showNoteSheet = false
                    }
                    .accessibilityIdentifier("pdfNoteSaveButton")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// Phase R4b: delegates to coordinator for highlight with note.
    func handleHighlightWithNote(
        event: ReaderSelectionEvent,
        container: ModelContainer,
        note: String?
    ) {
        let locator = viewModel.makeCurrentLocator()

        if let coordinator = highlightCoordinator {
            Task {
                await coordinator.create(
                    locator: locator,
                    anchor: event.anchor,
                    selectedText: event.selectedText,
                    color: "yellow",
                    note: note
                )
            }
        } else {
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                try? await persistence.addHighlight(
                    locator: locator, anchor: event.anchor,
                    selectedText: event.selectedText, color: "yellow",
                    note: note, toBookWithKey: viewModel.bookFingerprintKey
                )
            }
            pendingHighlightPayload = PDFHighlightNotificationPayload(
                anchor: event.anchor, color: "yellow"
            )
            pendingHighlightId += 1
        }
        pendingSelectionEvent = nil
    }
}
#endif
