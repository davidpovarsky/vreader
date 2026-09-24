// Purpose: Narrow main-actor PDFKit facade over the already-open/unlocked
// document shown by PDFView. No PDFKit object crosses the provider boundary.

#if canImport(PDFKit)
import PDFKit

@MainActor
final class AIPDFKitDocumentFacade: AIPDFDocumentFacading {
    private weak var document: PDFDocument?
    private weak var pdfView: PDFView?

    init(document: PDFDocument, pdfView: PDFView) {
        self.document = document
        self.pdfView = pdfView
    }

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    var currentPageIndex: Int? {
        guard let document,
              let currentPage = pdfView?.currentPage else { return nil }
        let index = document.index(for: currentPage)
        return index == NSNotFound ? nil : index
    }

    func text(forPage index: Int) async throws -> String {
        try Task.checkCancellation()
        guard let document, !document.isLocked else {
            throw AIDocumentProviderError.documentUnavailable
        }
        guard index >= 0, index < document.pageCount else { return "" }
        return document.page(at: index)?.string ?? ""
    }

    func isAttached(to candidate: PDFDocument) -> Bool {
        document === candidate
    }

    func detach() {
        document = nil
        pdfView = nil
    }
}
#endif
