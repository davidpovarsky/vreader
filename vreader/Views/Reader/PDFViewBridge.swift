// Purpose: UIViewRepresentable wrapping PDFKit's PDFView for PDF rendering.
// Provides page change notifications, page navigation, zoom control,
// text selection observation, highlight annotation lifecycle,
// and password unlock delegation back to the ViewModel.
//
// Key decisions:
// - Uses PDFKit (system framework) for rendering — no third-party dependencies.
// - Coordinator calls ViewModel directly (avoids protocol conformance issues on struct).
// - Page change notification via NotificationCenter (PDFViewPageChanged).
// - Selection change notification via PDFViewSelectionChanged — posts ReaderSelectionEvent.
// - Zoom level configurable; defaults to autoScale for fit-width.
// - Non-editable: read-only display mode.
// - restorePage applied once after document loads.
// - Tap gesture gated on currentSelection == nil to avoid clearing active selection.
// - Highlight restoration and creation processed via updateUIView from container state.
//
// @coordinates-with: PDFReaderViewModel.swift, PDFReaderContainerView.swift,
//   PDFAnnotationBridge.swift, ReaderNotifications.swift

#if canImport(UIKit)
import SwiftUI
import PDFKit

/// SwiftUI wrapper for PDFKit's PDFView.
struct PDFViewBridge: UIViewRepresentable {
    let url: URL
    var restorePage: Int?
    var password: String?
    /// Incremented on each password submission to trigger re-unlock even with same password.
    var passwordAttemptId: Int = 0
    let viewModel: PDFReaderViewModel
    /// Highlight records to restore as visible annotations. Processed once after document loads.
    var highlightRecords: [HighlightRecord]?
    /// Anchor + color for a newly created highlight. Processed once then cleared via the ID.
    var pendingHighlight: PDFHighlightNotificationPayload?
    /// Incremented each time a new highlight is created, to trigger processing in updateUIView.
    var pendingHighlightId: Int = 0

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        // Accessibility
        pdfView.accessibilityIdentifier = "pdfView"

        context.coordinator.pdfView = pdfView
        context.coordinator.viewModel = viewModel

        // Tap gesture for toolbar toggle (bug #32 — same pattern as TXT #21)
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapGesture.delegate = context.coordinator
        pdfView.addGestureRecognizer(tapGesture)

        // Observe page changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageDidChange(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        // Observe selection changes for annotation pipeline
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionDidChange(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )

        loadDocument(into: pdfView, coordinator: context.coordinator)

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Handle password retry: if attempt ID changed, try unlocking
        if let password,
           passwordAttemptId != context.coordinator.lastPasswordAttemptId,
           let document = pdfView.document, document.isLocked {
            context.coordinator.lastPasswordAttemptId = passwordAttemptId
            let unlocked = document.unlock(withPassword: password)
            if unlocked {
                let totalPages = document.pageCount
                viewModel.passwordAccepted(totalPages: totalPages)
                // Restore page after unlock
                if let page = restorePage,
                   page < document.pageCount,
                   let pdfPage = document.page(at: page) {
                    pdfView.go(to: pdfPage)
                }
            } else {
                viewModel.passwordRejected()
            }
        }

        // Navigate to page if requested and not yet applied
        if let page = restorePage,
           context.coordinator.lastRestoredPage != page,
           let document = pdfView.document,
           !document.isLocked {
            context.coordinator.lastRestoredPage = page
            if page < document.pageCount, let pdfPage = document.page(at: page) {
                pdfView.go(to: pdfPage)
            }
        }

        // Restore saved highlights (once, after document loads)
        if let records = highlightRecords,
           !context.coordinator.didRestoreHighlights,
           let document = pdfView.document,
           !document.isLocked {
            context.coordinator.didRestoreHighlights = true
            PDFAnnotationBridge.restoreHighlights(for: document, from: records)
        }

        // Create visible annotation for a newly persisted highlight
        if let highlight = pendingHighlight,
           pendingHighlightId != context.coordinator.lastPendingHighlightId,
           let document = pdfView.document,
           !document.isLocked {
            context.coordinator.lastPendingHighlightId = pendingHighlightId
            PDFAnnotationBridge.createHighlightFromAnchor(
                highlight.anchor, color: highlight.color, in: document
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Private

    private func loadDocument(into pdfView: PDFView, coordinator: Coordinator) {
        let fileURL = url
        let pwd = password
        let restorePage = restorePage
        let viewModel = viewModel

        Task.detached {
            guard let document = PDFDocument(url: fileURL) else {
                await MainActor.run {
                    viewModel.documentDidFailToLoad(error: "Failed to load PDF document.")
                }
                return
            }

            await MainActor.run {
                pdfView.document = document

                if document.isLocked {
                    if let pwd, document.unlock(withPassword: pwd) {
                        viewModel.documentDidLoad(totalPages: document.pageCount)
                    } else {
                        viewModel.documentNeedsPassword()
                    }
                } else {
                    let totalPages = document.pageCount
                    viewModel.documentDidLoad(totalPages: totalPages)

                    if let page = restorePage, page < totalPages,
                       let pdfPage = document.page(at: page) {
                        coordinator.lastRestoredPage = page
                        pdfView.go(to: pdfPage)
                    }
                }
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var viewModel: PDFReaderViewModel?
        weak var pdfView: PDFView?
        /// Tracks the last restored page to avoid re-applying on every updateUIView.
        var lastRestoredPage: Int?
        /// Tracks the last password attempt ID to detect retries (including same password).
        var lastPasswordAttemptId: Int = 0
        /// Whether saved highlights have been restored on this document.
        var didRestoreHighlights: Bool = false
        /// Tracks the last processed pending highlight ID to avoid re-creating.
        var lastPendingHighlightId: Int = 0

        @objc func pageDidChange(_ notification: Notification) {
            guard let pdfView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else {
                return
            }
            let pageIndex = document.index(for: currentPage)
            viewModel?.pageDidChange(to: pageIndex)
        }

        @objc func selectionDidChange(_ notification: Notification) {
            guard let pdfView,
                  let selection = pdfView.currentSelection,
                  let selectedText = selection.string,
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let document = pdfView.document else {
                return
            }

            // Get selection pages and rects
            let selectionPages = selection.selectionsByLine()
            var allRects: [CGRect] = []
            var firstPageIndex: Int?

            for lineSelection in selectionPages {
                guard let pages = lineSelection.pages as? [PDFPage] else { continue }
                for page in pages {
                    let pageIndex = document.index(for: page)
                    if firstPageIndex == nil { firstPageIndex = pageIndex }
                    let bounds = lineSelection.bounds(for: page)
                    if bounds != .zero {
                        allRects.append(bounds)
                    }
                }
            }

            guard let pageIndex = firstPageIndex,
                  let page = document.page(at: pageIndex),
                  !allRects.isEmpty else {
                return
            }

            let pageBounds = page.bounds(for: .mediaBox)

            // Convert first rect to screen coordinates for popup positioning
            let firstRect = allRects[0]
            let screenRect: CGRect
            if let convertedRect = pdfView.convert(firstRect, from: page) as CGRect? {
                screenRect = pdfView.convert(convertedRect, to: nil)
            } else {
                screenRect = firstRect
            }

            let event = PDFAnnotationBridge.makeSelectionEvent(
                selectedText: selectedText,
                pageIndex: pageIndex,
                viewRects: allRects,
                pageBounds: pageBounds,
                sourceRect: screenRect
            )

            NotificationCenter.default.post(
                name: .readerTextSelected,
                object: event
            )
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            // Gate tap on no active selection to avoid clearing selection
            if let pdfView, pdfView.currentSelection != nil {
                return
            }
            NotificationCenter.default.post(name: .readerContentTapped, object: nil)
        }

        // Allow tap gesture to fire alongside PDFView's internal gestures
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
#endif
