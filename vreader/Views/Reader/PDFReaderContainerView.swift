// Purpose: SwiftUI container for the PDF reader. Composes the PDFViewBridge
// with loading/error/password overlays, reading progress bar, session chrome,
// and PDF text selection / highlight annotation pipeline.
//
// Key decisions:
// - Owns PDFReaderViewModel lifecycle (close on disappear).
// - Bridge calls ViewModel directly (no delegate protocol needed).
// - Bridge is always mounted; loading/password/error are overlays.
// - Shows password prompt overlay for encrypted PDFs.
// - ReadingProgressBar wired via PDFProgressHelper for page-level scrubbing.
// - Page indicator and session time overlay at bottom.
// - Observes .readerTextSelected for PDF annotation creation via PDFAnnotationBridge.
// - Text selection triggers confirmationDialog with Highlight/Note/Copy actions.
// - "Add Note" opens a TextEditor sheet and persists highlight with note text.
// - Highlights stored in SwiftData (non-destructive — not written into the PDF file).
// - After persisting a highlight, passes anchor to bridge for visible annotation creation.
// - On document open, fetches saved highlights and passes to bridge for restoration.
// - Posts .readerPositionDidChange notification for AI panel live locator.
//
// @coordinates-with: PDFReaderViewModel.swift, PDFViewBridge.swift,
//   PDFPasswordPromptView.swift, ReadingProgressBar.swift, PDFProgressHelper.swift,
//   PDFAnnotationBridge.swift, HighlightPersisting.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData
import PDFKit
import UIKit

/// Container view for the PDF reader screen.
struct PDFReaderContainerView: View {
    let fileURL: URL
    let viewModel: PDFReaderViewModel
    var modelContainer: ModelContainer?

    @State private var password: String = ""
    @State private var submittedPassword: String?
    @State private var passwordAttemptId: Int = 0
    @State private var restoredPage: Int?
    @State private var readingProgress: Double = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Mirrors ReaderContainerView's chrome toggle so the bottom overlay hides with the nav bar.
    @State private var isChromeVisible = true
    /// Pending PDF text selection event for highlight action menu.
    @State private var pendingSelectionEvent: ReaderSelectionEvent?
    /// Whether the highlight action sheet is visible.
    @State private var showHighlightSheet = false
    /// Saved highlights to restore as visible annotations when the document loads.
    @State private var savedHighlightRecords: [HighlightRecord]?
    /// Pending highlight to create as a visible annotation after persist.
    @State private var pendingHighlightPayload: PDFHighlightNotificationPayload?
    /// Incremented each time a new highlight is persisted, triggers updateUIView.
    @State private var pendingHighlightId: Int = 0
    /// Whether the note input sheet is visible.
    @State private var showNoteSheet = false
    /// Text input for the note being added.
    @State private var noteText = ""
    /// Temporary search highlight text quote for navigating to search results (bug #43).
    /// Set when receiving .readerNavigateToLocator with textQuote, cleared after display.
    @State private var searchHighlightText: String?

    var body: some View {
        ZStack {
            // Bridge is always mounted so PDFDocument stays loaded
            PDFViewBridge(
                url: fileURL,
                restorePage: restoredPage,
                password: submittedPassword,
                passwordAttemptId: passwordAttemptId,
                viewModel: viewModel,
                highlightRecords: savedHighlightRecords,
                pendingHighlight: pendingHighlightPayload,
                pendingHighlightId: pendingHighlightId,
                searchHighlightText: searchHighlightText
            )
            .ignoresSafeArea(edges: .bottom)
            .accessibilityIdentifier("pdfReaderContent")

            // Overlays on top of the bridge
            if viewModel.needsPassword {
                passwordOverlay
            }

            if viewModel.isLoading {
                loadingOverlay
            }

            if let errorMessage = viewModel.errorMessage, !viewModel.isDocumentLoaded {
                errorOverlay(message: errorMessage)
            }

            // Bottom overlay for progress bar, page indicator, and session time
            if viewModel.isDocumentLoaded && isChromeVisible {
                VStack(spacing: 0) {
                    Spacer()
                    progressBar
                    bottomOverlay
                }
            }
        }
        .task {
            viewModel.beginLoading()
        }
        .onDisappear {
            let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            Task {
                await viewModel.close()
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                Task {
                    await viewModel.onBackground()
                    if bgTaskID != .invalid {
                        UIApplication.shared.endBackgroundTask(bgTaskID)
                    }
                }
            case .active:
                viewModel.onForeground()
            @unknown default:
                break
            }
        }
        .task(id: viewModel.isDocumentLoaded) {
            if viewModel.isDocumentLoaded {
                try? viewModel.startSession()
                restoredPage = await viewModel.restorePosition()
                await viewModel.updateLastOpened()
                // Restore saved highlights as visible annotations
                if let container = modelContainer {
                    let persistence = PersistenceActor(modelContainer: container)
                    let records = try? await persistence.fetchHighlights(
                        forBookWithKey: viewModel.bookFingerprintKey
                    )
                    if let records, !records.isEmpty {
                        savedHighlightRecords = records
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerBookmarkRequested)) { _ in
            guard let container = modelContainer, viewModel.isDocumentLoaded else { return }
            let persistence = PersistenceActor(modelContainer: container)
            let locator = viewModel.makeCurrentLocator()
            Task {
                try? await persistence.addBookmark(
                    locator: locator,
                    title: nil,
                    toBookWithKey: viewModel.bookFingerprintKey
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            isChromeVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNavigateToLocator)) { notification in
            guard let locator = notification.object as? Locator,
                  let page = locator.page else { return }
            restoredPage = page
            viewModel.pageDidChange(to: page)
            // Show search highlight at the match location (bug #43)
            if let textQuote = locator.textQuote,
               !textQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchHighlightText = textQuote
            }
        }
        .onChange(of: viewModel.currentPageIndex) { _, _ in
            readingProgress = PDFProgressHelper.progressForPage(
                currentPageIndex: viewModel.currentPageIndex,
                totalPages: viewModel.totalPages
            )
            // Notify ReaderContainerView of the live position for AI panel.
            let locator = viewModel.makeCurrentLocator()
            NotificationCenter.default.post(
                name: .readerPositionDidChange, object: locator
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerTextSelected)) { notification in
            guard let event = notification.object as? ReaderSelectionEvent else { return }
            pendingSelectionEvent = event
            showHighlightSheet = true
        }
        .confirmationDialog(
            "Text Selection",
            isPresented: $showHighlightSheet,
            titleVisibility: .visible
        ) {
            Button("Highlight") {
                guard let event = pendingSelectionEvent,
                      let container = modelContainer else { return }
                handleHighlightAction(event: event, container: container)
            }
            Button("Add Note") {
                noteText = ""
                showNoteSheet = true
            }
            Button("Copy") {
                guard let event = pendingSelectionEvent else { return }
                UIPasteboard.general.string = event.selectedText
            }
            Button("Cancel", role: .cancel) {
                pendingSelectionEvent = nil
            }
        }
        .sheet(isPresented: $showNoteSheet) {
            pdfNoteInputSheet
        }
        .accessibilityIdentifier("pdfReaderContainer")
    }

    // MARK: - Overlays

    @ViewBuilder
    private var passwordOverlay: some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
        PDFPasswordPromptView(
            password: $password,
            errorMessage: viewModel.errorMessage,
            onSubmit: {
                passwordAttemptId += 1
                submittedPassword = password
            },
            onCancel: {
                dismiss()
            }
        )
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        Color(.systemBackground).opacity(0.9)
            .ignoresSafeArea()
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("pdfReaderLoading")
    }

    private func errorOverlay(message: String) -> some View {
        ZStack {
            Color(.systemBackground).opacity(0.9)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .accessibilityIdentifier("pdfReaderError")
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        ReadingProgressBar(
            progress: $readingProgress,
            onSeek: { seekValue in
                let targetPage = PDFProgressHelper.pageForSeekValue(
                    seekValue: seekValue, totalPages: viewModel.totalPages
                )
                restoredPage = targetPage
                viewModel.pageDidChange(to: targetPage)
            },
            discreteSteps: PDFProgressHelper.discreteSteps(totalPages: viewModel.totalPages),
            isVisible: PDFProgressHelper.shouldShowProgressBar(
                isDocumentLoaded: viewModel.isDocumentLoaded,
                totalPages: viewModel.totalPages
            ),
            label: PDFProgressHelper.pageLabel(
                currentPageIndex: viewModel.currentPageIndex,
                totalPages: viewModel.totalPages
            )
        )
        .accessibilityIdentifier("pdfReadingProgressBar")
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        HStack {
            Text(viewModel.pageIndicator)
                .font(.caption)
                .monospacedDigit()
                .accessibilityLabel("Page \(viewModel.currentPageIndex + 1) of \(viewModel.totalPages)")
                .accessibilityIdentifier("pdfPageIndicator")

            Spacer()

            if let sessionTime = viewModel.sessionTimeDisplay {
                Text(sessionTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pdfSessionTime")
            }

            if let pph = viewModel.pagesPerHour {
                Text("~\(Int(pph.rounded())) pages/hr")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pdfPagesPerHour")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .accessibilityIdentifier("pdfBottomOverlay")
    }

    // MARK: - Highlight Actions

    private func handleHighlightAction(
        event: ReaderSelectionEvent,
        container: ModelContainer
    ) {
        let persistence = PersistenceActor(modelContainer: container)
        let locator = viewModel.makeCurrentLocator()
        let anchor = event.anchor

        Task {
            try? await persistence.addHighlight(
                locator: locator,
                anchor: anchor,
                selectedText: event.selectedText,
                color: "yellow",
                note: nil,
                toBookWithKey: viewModel.bookFingerprintKey
            )
        }
        // Create visible annotation immediately (bridge processes in updateUIView)
        pendingHighlightPayload = PDFHighlightNotificationPayload(
            anchor: anchor, color: "yellow"
        )
        pendingHighlightId += 1
        pendingSelectionEvent = nil
    }

    // MARK: - Note Input Sheet

    @ViewBuilder
    private var pdfNoteInputSheet: some View {
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

    /// Persists a highlight with an attached note and creates a visible annotation.
    private func handleHighlightWithNote(
        event: ReaderSelectionEvent,
        container: ModelContainer,
        note: String?
    ) {
        let persistence = PersistenceActor(modelContainer: container)
        let locator = viewModel.makeCurrentLocator()
        let anchor = event.anchor

        Task {
            try? await persistence.addHighlight(
                locator: locator,
                anchor: anchor,
                selectedText: event.selectedText,
                color: "yellow",
                note: note,
                toBookWithKey: viewModel.bookFingerprintKey
            )
        }
        pendingHighlightPayload = PDFHighlightNotificationPayload(
            anchor: anchor, color: "yellow"
        )
        pendingHighlightId += 1
        pendingSelectionEvent = nil
    }
}
#endif
