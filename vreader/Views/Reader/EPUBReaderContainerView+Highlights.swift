// Purpose: Highlight action handling, note input sheet, and highlight restoration
// for EPUBReaderContainerView. Pure code extraction — no logic changes.
//
// @coordinates-with: EPUBReaderContainerView.swift, EPUBHighlightActions.swift,
//   EPUBHighlightBridge.swift, EPUBHighlightRenderer.swift, HighlightCoordinator.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData

extension EPUBReaderContainerView {

    // MARK: - Highlight Actions

    /// Persists a highlight and injects the CSS highlight into the WKWebView.
    /// Phase R4b: delegates to coordinator (which calls renderer for JS injection).
    func handleHighlightAction(
        event: ReaderSelectionEvent,
        container: ModelContainer
    ) {
        guard let locator = viewModel.makeCurrentLocator() else {
            pendingSelectionEvent = nil
            return
        }

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
            // Fallback: direct persistence if coordinator not ready
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                if let record = try? await EPUBHighlightActions.persistHighlight(
                    event: event, locator: locator,
                    persistence: persistence, bookKey: viewModel.bookFingerprintKey
                ), let js = EPUBHighlightActions.createHighlightJS(for: record) {
                    pendingHighlightJS = js
                }
            }
        }
        pendingSelectionEvent = nil
    }

    // MARK: - Note Input Sheet

    @ViewBuilder
    var noteInputSheet: some View {
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
                    .accessibilityIdentifier("epubNoteTextEditor")
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
                    .accessibilityIdentifier("epubNoteCancelButton")
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
                    .accessibilityIdentifier("epubNoteSaveButton")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// Persists a highlight with an attached note.
    /// Phase R4b: delegates to coordinator.
    func handleHighlightWithNote(
        event: ReaderSelectionEvent,
        container: ModelContainer,
        note: String?
    ) {
        guard let locator = viewModel.makeCurrentLocator() else {
            pendingSelectionEvent = nil
            return
        }

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
            // Fallback: direct persistence if coordinator not ready
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                if let record = try? await persistence.addHighlight(
                    locator: locator, anchor: event.anchor,
                    selectedText: event.selectedText, color: "yellow",
                    note: note, toBookWithKey: viewModel.bookFingerprintKey
                ), let js = EPUBHighlightActions.createHighlightJS(for: record) {
                    pendingHighlightJS = js
                }
            }
        }
        pendingSelectionEvent = nil
    }

    /// Restores saved highlights for the current chapter after a page finishes loading.
    /// Phase R4b: delegates to coordinator which calls EPUBHighlightRenderer.
    func restoreHighlightsOnLoad(evaluateJS: @escaping (String) -> Void) {
        guard let href = viewModel.currentPosition?.href else { return }
        highlightRenderer.currentHref = href

        if let coordinator = highlightCoordinator {
            // Temporarily redirect renderer output to the evaluateJS closure
            // for immediate injection (page is ready now).
            let originalCallback = highlightRenderer.onInjectJS
            highlightRenderer.onInjectJS = evaluateJS
            Task {
                await coordinator.restoreAll()
                highlightRenderer.onInjectJS = originalCallback
            }
        } else {
            // Fallback: direct fetch if coordinator not ready
            guard let container = modelContainer else { return }
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                let highlights = (try? await persistence.fetchHighlights(
                    forBookWithKey: viewModel.bookFingerprintKey
                )) ?? []
                let js = EPUBHighlightActions.restoreHighlightsJS(
                    highlights: highlights, currentHref: href
                )
                if !js.isEmpty { evaluateJS(js) }
            }
        }
    }
}
#endif
